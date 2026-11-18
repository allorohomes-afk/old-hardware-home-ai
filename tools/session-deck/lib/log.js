// "Save to log": summarize a session with the local Ollama (nothing leaves this Mac) and append it to today's
// run log (<runLogFolder>/Run-YYYY-MM-DD.md) in a Markdown notes vault, through its Local REST API plugin (config.notes).
import { execFileSync } from 'node:child_process'
import { readMessages } from './sessions.js'
import { config } from './config.js'

const OLLAMA = 'http://127.0.0.1:11434'
const MODEL = config.summaryModel
const OB = config.notes

function notesToken() {
  return execFileSync('security', ['find-generic-password', '-s', OB.keychainService, '-a', OB.keychainAccount, '-w'], { encoding: 'utf8' }).trim()
}

async function notesApi(method, path, body) {
  // the REST API plugin uses a self-signed certificate on 127.0.0.1; trust it for this one local call only
  const { Agent } = await import('undici').catch(() => ({}))
  const opts = { method, headers: { Authorization: `Bearer ${notesToken()}`, 'Content-Type': 'text/markdown' }, body }
  if (Agent) opts.dispatcher = new Agent({ connect: { rejectUnauthorized: false } })
  return fetch(OB.url + path, opts)
}

async function summarize(title, messages) {
  const convo = messages.map((m) => `${m.role === 'user' ? 'USER' : 'CLAUDE'}: ${m.text}`).join('\n\n').slice(-14000)
  const prompt = `Summarize this Claude Code work session for a work log. Facts only, no praise, no invention.
Reply in exactly this format:
WHAT: <2-4 short sentences: what was done and decided>
STATUS: <one line: done / in progress / blocked, plus anything left open>

Session title: ${title}

${convo}`
  const r = await fetch(OLLAMA + '/api/generate', {
    method: 'POST',
    body: JSON.stringify({ model: MODEL, prompt, stream: false, options: { temperature: 0.2, num_ctx: 8192 } }),
    signal: AbortSignal.timeout(180_000),
  })
  if (!r.ok) throw new Error(`Ollama ${r.status}`)
  const out = (await r.json()).response || ''
  const what = (out.match(/WHAT:\s*([\s\S]*?)(?:\n\s*STATUS:|$)/i) || [])[1]?.trim()
  const status = (out.match(/STATUS:\s*(.*)/i) || [])[1]?.trim()
  return { what: what || out.trim(), status: status || 'see session' }
}

export async function saveToLog(session) {
  if (!OB) throw new Error(`the notes log isn't set up: add "notes" to ${config.file}`)
  const { title, messages } = readMessages(session.sessionId, 80)
  if (!messages.length) throw new Error('nothing in this session to log yet')
  const name = title || session.name
  let sum
  try { sum = await summarize(name, messages) }
  catch (e) { // Ollama off: log the last requests instead of a summary
    const asks = messages.filter((m) => m.role === 'user').slice(-4).map((m) => m.text.slice(0, 160).replace(/\s+/g, ' '))
    sum = { what: `Recent requests: ${asks.join(' / ')}`, status: `(no summary: ${e.message})` }
  }
  const now = new Date()
  const hhmm = now.toTimeString().slice(0, 5)
  const day = now.toLocaleDateString('en-CA')
  const entry = `\n## ${hhmm} — ${name}${OB.signature ? ' • ' + OB.signature : ''}\n- **Agent:** Claude Code session \`${session.name}\` (${session.folder})\n- **Mode:** saved from Session Deck\n- **What:** ${sum.what.replace(/\n+/g, ' ')}\n- **Status:** ${sum.status}\n- **Session:** \`${session.sessionId}\`\n`
  const folder = OB.runLogFolder.split('/').map(encodeURIComponent).join('/')
  const path = `/vault/${folder}/Run-${day}.md`
  let r = await notesApi('POST', path, entry)
  if (r.status === 404) r = await notesApi('PUT', path, `# Run Log — ${day}\n` + entry)
  if (!r.ok) throw new Error(`the notes vault answered ${r.status} (is the notes app open?)`)
  return { entry, file: `${OB.runLogFolder}/Run-${day}.md` }
}
