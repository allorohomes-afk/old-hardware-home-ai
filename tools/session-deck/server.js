// Session Deck: one window for every Claude Code session on the Air.
// Left: open sessions (busy/idle, bridged) with a ⋯ menu. Right: the live session in a real terminal (tmux-hosted
// sessions) or its transcript (sessions open in Terminal tabs).
// Only this Mac can reach it: 127.0.0.1, a per-launch token, and Host/Origin checks, because the terminal can run
// anything Claude Code can.
import http from 'node:http'
import { readFileSync, writeFileSync, existsSync, mkdirSync, copyFileSync } from 'node:fs'
import { execFileSync, spawn } from 'node:child_process'
import { randomBytes } from 'node:crypto'
import { homedir } from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { WebSocketServer } from 'ws'
import pty from 'node-pty'
import { listSessions, readMessages } from './lib/sessions.js'
import { saveToLog } from './lib/log.js'
import { saveAllToHive } from './lib/hive.js'

const PORT = Number(process.env.DECK_PORT || 5199)
const HERE = path.dirname(fileURLToPath(import.meta.url))
const STATE = path.join(homedir(), '.session-deck')
const TOKEN = randomBytes(24).toString('hex')
const HOSTS = new Set([`127.0.0.1:${PORT}`, `localhost:${PORT}`])
const CLAUDE_CFG = path.join(homedir(), 'Library/Application Support/Claude/claude_desktop_config.json')
mkdirSync(STATE, { recursive: true })
// sessions started here must be normal top-level sessions, not children of whatever Claude launched the deck
for (const k of Object.keys(process.env)) if (k.startsWith('CLAUDE_CODE_') || k === 'CLAUDECODE' || k === 'CLAUDE_PID') delete process.env[k]

const VENDOR = {
  '/vendor/xterm.js': 'node_modules/@xterm/xterm/lib/xterm.js',
  '/vendor/xterm.css': 'node_modules/@xterm/xterm/css/xterm.css',
  '/vendor/addon-fit.js': 'node_modules/@xterm/addon-fit/lib/addon-fit.js',
}

const send = (res, status, body, type = 'application/json') => {
  res.writeHead(status, { 'Content-Type': type, 'Cache-Control': 'no-store', 'X-Frame-Options': 'DENY' })
  res.end(type === 'application/json' ? JSON.stringify(body) : body)
}
const body = (req) => new Promise((ok) => { let s = ''; req.on('data', (c) => (s += c)); req.on('end', () => { try { ok(JSON.parse(s || '{}')) } catch { ok({}) } }) })
const sameOrigin = (req) => HOSTS.has(req.headers.host) && (!req.headers.origin || HOSTS.has(req.headers.origin.replace(/^http:\/\//, '')))
const tmux = (...a) => execFileSync('tmux', a, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })

function bridgeStatus() {
  let configured = false
  try { configured = !!JSON.parse(readFileSync(CLAUDE_CFG, 'utf8')).mcpServers?.['session-deck'] } catch {}
  let lastSeen = null
  try { lastSeen = JSON.parse(readFileSync(path.join(STATE, 'mcp-seen.json'), 'utf8')).at } catch {}
  let shared = []
  try { shared = JSON.parse(readFileSync(path.join(STATE, 'shared.json'), 'utf8')) } catch {}
  const running = (pattern, exact) => { try { execFileSync('pgrep', exact ? ['-x', pattern] : ['-f', pattern], { stdio: 'ignore' }); return true } catch { return false } }
  const appRunning = running('Claude', true)
  const loaded = running('session-deck/mcp.js') // the Claude app starts mcp.js itself once it has loaded the bridge
  return { configured, lastSeen, appRunning, loaded, needsRestart: configured && appRunning && !loaded, shared: shared.map((s) => s.sessionId) }
}

function connectClaudeApp() {
  let cfg = {}
  if (existsSync(CLAUDE_CFG)) {
    copyFileSync(CLAUDE_CFG, CLAUDE_CFG + '.bak-session-deck')
    cfg = JSON.parse(readFileSync(CLAUDE_CFG, 'utf8'))
  }
  cfg.mcpServers = { ...(cfg.mcpServers || {}), 'session-deck': { command: existsSync('/opt/homebrew/bin/node') ? '/opt/homebrew/bin/node' : process.execPath, args: [path.join(HERE, 'mcp.js')] } }
  writeFileSync(CLAUDE_CFG, JSON.stringify(cfg, null, 2))
}

function find(id) {
  const s = listSessions().find((x) => x.sessionId === id)
  if (!s) throw Object.assign(new Error('session not found (it may have ended)'), { status: 404 })
  return s
}

async function api(req, res, url) {
  const p = url.pathname
  if (p === '/api/sessions') return send(res, 200, { sessions: listSessions(), bridge: bridgeStatus() })
  if (p === '/api/transcript') return send(res, 200, readMessages(url.searchParams.get('id') || '', 60))
  if (req.method !== 'POST') return send(res, 405, { error: 'POST only' })
  const b = await body(req)

  if (p === '/api/new') {
    const cwd = path.resolve(String(b.cwd || '~').replace(/^~(?=$|\/)/, homedir()))
    if (!existsSync(cwd)) return send(res, 400, { error: `no such folder: ${cwd}` })
    const name = 'deck-' + Date.now().toString(36).slice(-5)
    tmux('new-session', '-d', '-s', name, '-x', '200', '-y', '50', '-c', cwd, 'claude')
    tmux('set-option', '-t', name, 'window-size', 'latest'); tmux('set-option', '-t', name, 'mouse', 'on'); tmux('set-option', '-t', name, 'status', 'off') // deck and a popped-out window can both be attached
    return send(res, 200, { tmux: name })
  }
  if (p === '/api/save') {
    const out = await saveToLog(find(b.id))
    return send(res, 200, out)
  }
  if (p === '/api/send') { // share with the Claude app: listed by the MCP tool shared_sessions, prompt on the clipboard
    const s = find(b.id)
    const file = path.join(STATE, 'shared.json')
    let shared = []; try { shared = JSON.parse(readFileSync(file, 'utf8')) } catch {}
    shared = [{ sessionId: s.sessionId, title: s.title, at: new Date().toISOString() }, ...shared.filter((x) => x.sessionId !== s.sessionId)].slice(0, 20)
    writeFileSync(file, JSON.stringify(shared, null, 2))
    const prompt = `Use the session-deck tools to read my Claude Code session "${s.title}" (id ${s.sessionId}) and review it: what was done, anything risky or unfinished, and what I should do next.`
    const pb = spawn('pbcopy'); pb.stdin.end(prompt)
    spawn('open', ['-a', 'Claude'])
    return send(res, 200, { prompt })
  }
  if (p === '/api/end') {
    const s = find(b.id)
    let saved = null
    if (b.save) saved = await saveToLog(s) // a failed save throws, so the session stays open
    if (s.tmux) tmux('kill-session', '-t', s.tmux)
    else process.kill(s.pid, 'SIGTERM')
    return send(res, 200, { ended: true, saved })
  }
  if (p === '/api/move') { // a Terminal-tab session -> live in the deck: close it there, resume the same conversation in tmux
    const s = find(b.id)
    if (s.tmux) return send(res, 400, { error: 'already in the deck' })
    if (s.status !== 'idle') return send(res, 409, { error: 'it is busy; wait until it finishes, then move it' })
    process.kill(s.pid, 'SIGTERM')
    for (let i = 0; i < 40; i++) {
      await new Promise((r) => setTimeout(r, 250))
      try { process.kill(s.pid, 0) } catch { break }
      if (i === 39) return send(res, 500, { error: "it didn't close; nothing was moved" })
    }
    const name = 'deck-' + Date.now().toString(36).slice(-5)
    tmux('new-session', '-d', '-s', name, '-x', '200', '-y', '50', '-c', s.cwd, 'claude', '--resume', s.sessionId)
    tmux('set-option', '-t', name, 'window-size', 'latest'); tmux('set-option', '-t', name, 'mouse', 'on'); tmux('set-option', '-t', name, 'status', 'off')
    return send(res, 200, { tmux: name })
  }
  if (p === '/api/popout') { // Outlook-style pop out: the session in its own Terminal window, in front
    const s = find(b.id)
    const script = s.tmux
      ? `tell application "Terminal"\n  do script "tmux attach-session -t ${s.tmux}"\n  activate\nend tell`
      : `set t to "/dev/${execFileSync('ps', ['-o', 'tty=', '-p', String(s.pid)], { encoding: 'utf8' }).trim()}"
tell application "Terminal"
  repeat with w in windows
    repeat with k in tabs of w
      if tty of k is t then
        set selected of k to true
        set index of w to 1
        activate
        return "ok"
      end if
    end repeat
  end repeat
end tell
return "not found"`
    const out = execFileSync('osascript', ['-e', script], { encoding: 'utf8' }).trim()
    if (out === 'not found') return send(res, 404, { error: "couldn't find its Terminal window (it may be in another app, like iTerm or tmux)" })
    return send(res, 200, { ok: true })
  }
  if (p === '/api/hive/save-all') return send(res, 200, await saveAllToHive())
  if (p === '/api/claude-app') { // Start Claude: open it (or bring it forward); restart = quit, wait, reopen so it loads the bridge
    if (b.restart) {
      try { execFileSync('osascript', ['-e', 'tell application "Claude" to quit'], { stdio: 'ignore', timeout: 15000 }) } catch {}
      for (let i = 0; i < 40; i++) {
        try { execFileSync('pgrep', ['-x', 'Claude'], { stdio: 'ignore' }) } catch { break }
        await new Promise((r) => setTimeout(r, 250))
      }
    }
    execFileSync('open', ['-a', 'Claude'])
    return send(res, 200, bridgeStatus())
  }
  if (p === '/api/bridge/connect') { connectClaudeApp(); return send(res, 200, bridgeStatus()) }
  send(res, 404, { error: 'unknown' })
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`)
  if (!HOSTS.has(req.headers.host)) return send(res, 421, 'wrong host', 'text/plain')
  try {
    if (url.pathname === '/') {
      const html = readFileSync(path.join(HERE, 'public/index.html'), 'utf8').replace('__TOKEN__', TOKEN)
      return send(res, 200, html, 'text/html; charset=utf-8')
    }
    if (/^\/icons\/[\w-]+\.(png|svg)$/.test(url.pathname) || url.pathname === '/manifest.json') {
      const type = url.pathname.endsWith('.png') ? 'image/png' : url.pathname.endsWith('.svg') ? 'image/svg+xml' : 'application/manifest+json'
      return send(res, 200, readFileSync(path.join(HERE, 'public', url.pathname)), type)
    }
    if (VENDOR[url.pathname]) {
      return send(res, 200, readFileSync(path.join(HERE, VENDOR[url.pathname])), url.pathname.endsWith('.css') ? 'text/css' : 'text/javascript')
    }
    if (url.pathname.startsWith('/api/')) {
      if (!sameOrigin(req) || req.headers['x-deck-token'] !== TOKEN) return send(res, 403, { error: 'reload Session Deck' })
      return await api(req, res, url)
    }
    send(res, 404, 'not found', 'text/plain')
  } catch (e) {
    send(res, e.status || 500, { error: e.message })
  }
})

// live terminal: a pty running `tmux attach` for one tmux-hosted session
const wss = new WebSocketServer({ noServer: true })
server.on('upgrade', (req, socket, head) => {
  const url = new URL(req.url, `http://${req.headers.host}`)
  const name = url.searchParams.get('tmux') || ''
  if (url.pathname !== '/term' || !sameOrigin(req) || !req.headers.origin || url.searchParams.get('t') !== TOKEN || !/^[\w.-]+$/.test(name)) {
    socket.destroy(); return
  }
  wss.handleUpgrade(req, socket, head, (ws) => {
    const term = pty.spawn('tmux', ['attach-session', '-t', name], {
      name: 'xterm-256color', cols: 120, rows: 40, cwd: homedir(),
      env: { ...process.env, TERM: 'xterm-256color', LANG: process.env.LANG || 'en_US.UTF-8' },
    })
    term.onData((d) => ws.readyState === 1 && ws.send(d))
    term.onExit(() => ws.close())
    ws.on('message', (m) => {
      const s = m.toString()
      if (s.startsWith('\x00resize:')) { const [c, r] = s.slice(8).split('x').map(Number); if (c > 0 && r > 0) term.resize(c, r) }
      else term.write(s)
    })
    ws.on('close', () => term.kill()) // detaches only; the tmux session and Claude keep running
  })
})

server.listen(PORT, '127.0.0.1', () => console.log(`Session Deck on http://127.0.0.1:${PORT}`))
