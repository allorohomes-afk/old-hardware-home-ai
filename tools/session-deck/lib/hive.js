// "Save all sessions to the Hive": copy every Claude Code transcript on this Mac, plus a readable Markdown copy of
// each open session, to a home server over SSH (config.hive). Copies only; deletes nothing.
import { spawn, execFileSync } from 'node:child_process'
import { mkdirSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import path from 'node:path'
import { listSessions, readMessages } from './sessions.js'
import { config } from './config.js'

const H = config.hive
const SSH = [...(H?.sshOptions || []), '-o', 'ConnectTimeout=5', '-o', 'BatchMode=yes', '-o', 'ServerAliveInterval=30']
const EXPORTS = path.join(homedir(), '.session-deck/exports')

function run(cmd, args) {
  return new Promise((ok, fail) => {
    const p = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'] })
    let err = ''; p.stderr.on('data', (d) => (err += d))
    p.on('close', (code) => (code === 0 ? ok() : fail(new Error(err.trim().split('\n').pop() || `${cmd} exit ${code}`))))
  })
}

function exportReadable() {
  const day = new Date().toLocaleDateString('en-CA')
  const dir = path.join(EXPORTS, day)
  mkdirSync(dir, { recursive: true })
  const open = listSessions()
  for (const s of open) {
    const { title, messages } = readMessages(s.sessionId, 1e9, true)
    const name = `${(title || s.name).replace(/[^\w .-]+/g, '').trim().slice(0, 60) || 'session'} (${s.sessionId.slice(0, 8)}).md`
    const md = `# ${title || s.name}\n\n- Session: \`${s.sessionId}\` (${s.name})\n- Folder: ${s.folder}\n- Saved: ${new Date().toISOString()}\n\n` +
      messages.map((m) => `## ${m.role === 'user' ? config.userName : 'Claude'} · ${(m.time || '').slice(0, 16).replace('T', ' ')}\n\n${m.text}\n`).join('\n')
    writeFileSync(path.join(dir, name), md)
  }
  return open.length
}

export async function saveAllToHive() {
  if (!H) throw new Error(`no home server set up: add "hive" to ${config.file}`)
  const HOST = H.ssh, DEST = H.dest
  const check = (H.mountCheck ? `mountpoint -q ${H.mountCheck} && ` : '') + `mkdir -p ${DEST}/transcripts ${DEST}/readable`
  try {
    execFileSync('ssh', [...SSH, HOST, check], { stdio: 'ignore', timeout: 15000 })
  } catch {
    throw new Error(`${H.label} isn't reachable (not on the home network, or its storage isn't mounted)`)
  }
  const open = exportReadable()
  const e = ['-e', ['ssh', ...SSH].join(' ')]
  // full transcripts (raw .jsonl, every session ever on this Air) and the readable copies
  await run('/usr/bin/rsync', ['-rt', '--partial', '--include=*/', '--include=*.jsonl', '--exclude=*', ...e, path.join(homedir(), '.claude/projects') + '/', `${HOST}:${DEST}/transcripts/`])
  await run('/usr/bin/rsync', ['-rt', ...e, EXPORTS + '/', `${HOST}:${DEST}/readable/`])
  return { open, dest: `${H.label}:${DEST}` }
}
