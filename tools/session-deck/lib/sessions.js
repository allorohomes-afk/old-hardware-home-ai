// Reads Claude Code's own records of open sessions on this Mac. Read-only, shared by the dashboard and the MCP bridge.
//   ~/.claude/sessions/<pid>.json        one file per running session (name, folder, busy/idle, Remote Control bridge)
//   ~/.claude/projects/<dir>/<id>.jsonl  the conversation itself
import { readdirSync, readFileSync, existsSync, statSync, openSync, readSync, closeSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { homedir } from 'node:os'
import path from 'node:path'
import { config } from './config.js'

const HOME = homedir()
const REG = path.join(HOME, '.claude/sessions')
const PROJECTS = path.join(HOME, '.claude/projects')
const TAIL_BYTES = 3 * 1024 * 1024

function alive(pid) {
  try { process.kill(pid, 0); return true } catch (e) { return e.code === 'EPERM' }
}

// tmux pane pid -> tmux session name, so the dashboard knows which sessions it can open live
function tmuxPanes() {
  try {
    const out = execFileSync('tmux', ['list-panes', '-a', '-F', '#{pane_pid} #{session_name}'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] })
    return new Map(out.trim().split('\n').filter(Boolean).map((l) => { const [p, ...n] = l.split(' '); return [Number(p), n.join(' ')] }))
  } catch { return new Map() }
}

function parentPid(pid) {
  try { return Number(execFileSync('ps', ['-o', 'ppid=', '-p', String(pid)], { encoding: 'utf8' }).trim()) } catch { return 0 }
}

function tmuxFor(pid, panes) {
  for (let p = pid, hops = 0; p > 1 && hops < 6; p = parentPid(p), hops++) if (panes.has(p)) return panes.get(p)
  return null
}

export function transcriptPath(sessionId) {
  if (!/^[0-9a-f-]{36}$/.test(sessionId)) return null
  for (const dir of readdirSync(PROJECTS)) {
    const p = path.join(PROJECTS, dir, sessionId + '.jsonl')
    if (existsSync(p)) return p
  }
  return null
}

function readTail(file, full = false) {
  const size = statSync(file).size
  const start = full ? 0 : Math.max(0, size - TAIL_BYTES)
  const buf = Buffer.alloc(size - start)
  const fd = openSync(file, 'r'); readSync(fd, buf, 0, buf.length, start); closeSync(fd)
  const lines = buf.toString('utf8').split('\n')
  if (start > 0) lines.shift() // first line is cut
  return lines
}

function textOf(content) {
  if (typeof content === 'string') return content
  if (!Array.isArray(content)) return ''
  return content.filter((c) => c.type === 'text').map((c) => c.text).join('\n')
}

// User/assistant text only, oldest first. Skips tool calls, tool output, hooks and system notices.
export function readMessages(sessionId, limit = 40, full = false) {
  const file = transcriptPath(sessionId)
  if (!file) return { title: null, messages: [] }
  let title = null, lastPrompt = ''
  const msgs = []
  for (const line of readTail(file, full)) {
    if (!line) continue
    let d; try { d = JSON.parse(line) } catch { continue }
    if (d.type === 'ai-title' && d.aiTitle) title = d.aiTitle
    if (d.type === 'custom-title' && d.customTitle) title = d.customTitle
    if (d.type === 'last-prompt' && d.lastPrompt) lastPrompt = d.lastPrompt
    if ((d.type !== 'user' && d.type !== 'assistant') || d.isSidechain || d.isMeta || d.isCompactSummary) continue
    const text = textOf(d.message?.content)
      .replace(/<system-reminder>[\s\S]*?<\/system-reminder>/g, '')
      .replace(/<pasted_content[^>]*>([\s\S]*?)<\/pasted_content[^>]*>/g, '$1').trim()
    if (!text || text.startsWith('<task-notification>') || text.startsWith('<command-') || text.startsWith('<local-command')) continue
    msgs.push({ role: d.type, time: d.timestamp, text })
  }
  return { title, lastPrompt, messages: msgs.slice(-limit) }
}

export function listSessions() {
  const panes = tmuxPanes()
  const out = []
  let files = []
  try { files = readdirSync(REG).filter((f) => /^\d+\.json$/.test(f)) } catch {}
  for (const f of files) {
    let s; try { s = JSON.parse(readFileSync(path.join(REG, f), 'utf8')) } catch { continue }
    if (!s.sessionId || !alive(s.pid)) continue
    const { title, lastPrompt, messages } = readMessages(s.sessionId, 60)
    const lastUser = [...messages].reverse().find((m) => m.role === 'user')
    out.push({
      sessionId: s.sessionId,
      pid: s.pid,
      name: s.name,
      title: title || s.name,
      cwd: s.cwd,
      folder: s.cwd === HOME ? '~' : s.cwd.replace(HOME, '~'),
      kind: s.kind,
      status: s.status || 'unknown',
      updatedAt: s.statusUpdatedAt || s.updatedAt,
      startedAt: s.startedAt,
      bridged: !!s.bridgeSessionId,
      tmux: tmuxFor(s.pid, panes),
      lastPrompt: (lastPrompt || lastUser?.text || '').slice(0, 140),
    })
  }
  return out.sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0))
}

export function findSession(idOrName) {
  const q = String(idOrName || '').toLowerCase()
  return listSessions().find((s) => s.sessionId === q || s.sessionId.startsWith(q) || s.name.toLowerCase() === q || s.title.toLowerCase().includes(q))
}

// Keyword search across every transcript on this Mac (open and ended sessions). grep finds the files fast,
// then each match is parsed for the user/Claude messages that contain the words.
export function searchSessions(query, limit = 10) {
  const q = String(query || '').trim()
  if (!q) return []
  const words = q.toLowerCase().split(/\s+/)
  // fast byte search for the first word (a few casings) before any line parsing; newest files first, stop at `limit`
  const w0 = words[0]
  const variants = [...new Set([w0, w0[0].toUpperCase() + w0.slice(1), w0.toUpperCase()])].map((v) => Buffer.from(v))
  const files = []
  for (const dir of readdirSync(PROJECTS)) {
    let names = []; try { names = readdirSync(path.join(PROJECTS, dir)) } catch { continue }
    for (const n of names) if (n.endsWith('.jsonl')) { const f = path.join(PROJECTS, dir, n); files.push({ f, mtime: statSync(f).mtimeMs, id: n.slice(0, -6) }) }
  }
  files.sort((a, b) => b.mtime - a.mtime)
  const open = new Map(listSessions().map((s) => [s.sessionId, s]))
  const out = []
  for (const { f, mtime, id } of files) {
    if (out.length >= limit) break
    const buf = readFileSync(f)
    if (!variants.some((v) => buf.indexOf(v) !== -1)) continue
    // parse only lines that could match (or carry the title): full transcripts hold large base64 images
    let title = null
    const hits = []
    for (const line of buf.toString('utf8').split('\n')) {
      if (line.includes('"ai-title"')) { try { title = JSON.parse(line).aiTitle || title } catch {} continue }
      if (line.startsWith('{"type":"api-request') || line.startsWith('{"type":"file-history') || line.startsWith('{"type":"queue')) continue
      const low = line.toLowerCase()
      if (!words.every((w) => low.includes(w))) continue
      let d; try { d = JSON.parse(line) } catch { continue }
      if ((d.type !== 'user' && d.type !== 'assistant') || d.isSidechain || d.isMeta || d.isCompactSummary) continue
      const text = textOf(d.message?.content).replace(/<system-reminder>[\s\S]*?<\/system-reminder>/g, '').trim()
      const t = text.toLowerCase()
      if (text && words.every((w) => t.includes(w))) hits.push({ role: d.type, time: d.timestamp, text })
    }
    if (!hits.length) continue
    out.push({
      sessionId: id, title: title || id.slice(0, 8), open: open.has(id), status: open.get(id)?.status || 'ended',
      lastActive: new Date(mtime).toISOString(), matches: hits.length,
      snippets: hits.slice(-3).map((m) => {
        const i = Math.max(0, m.text.toLowerCase().indexOf(w0) - 80)
        return `${m.role === 'user' ? config.userName : 'Claude'} (${(m.time || '').slice(0, 10)}): …${m.text.slice(i, i + 240).replace(/\s+/g, ' ')}…`
      }),
    })
  }
  return out
}
