// Session Deck MCP bridge for the Claude desktop app (stdio, local only). Read-only: Claude can list and read the
// Claude Code sessions on this Mac, never type into them or change anything.
// Every call stamps ~/.session-deck/mcp-seen.json so the dashboard can show "Claude app connected".
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'
import { z } from 'zod'
import { writeFileSync, readFileSync, mkdirSync } from 'node:fs'
import { homedir } from 'node:os'
import path from 'node:path'
import { listSessions, readMessages, findSession, searchSessions } from './lib/sessions.js'
import { config } from './lib/config.js'

const STATE = path.join(homedir(), '.session-deck')
mkdirSync(STATE, { recursive: true })
const seen = () => { try { writeFileSync(path.join(STATE, 'mcp-seen.json'), JSON.stringify({ at: Date.now() })) } catch {} }
const text = (obj) => ({ content: [{ type: 'text', text: typeof obj === 'string' ? obj : JSON.stringify(obj, null, 2) }] })

const server = new McpServer({ name: 'session-deck', version: '0.1.0' })

server.registerTool('list_sessions', {
  description: `List ${config.userName}'s open Claude Code sessions on ${config.machineName}: title, folder, busy/idle, last request.`,
  inputSchema: {},
}, async () => {
  seen()
  return text(listSessions().map(({ sessionId, title, folder, status, bridged, tmux, lastPrompt, updatedAt }) =>
    ({ sessionId, title, folder, status, live_in_deck: !!tmux, remote_control: bridged, lastPrompt, updated: new Date(updatedAt).toISOString() })))
})

server.registerTool('read_session', {
  description: 'Read the conversation of one session (user and Claude messages only, oldest first). Use list_sessions first. Accepts the session id, its start, or part of its title.',
  inputSchema: { session: z.string().describe('session id, id prefix, or part of the title'), limit: z.number().int().min(1).max(200).optional().describe('how many recent messages (default 60)') },
}, async ({ session, limit }) => {
  seen()
  const s = findSession(session)
  const id = s ? s.sessionId : session
  const { title, messages } = readMessages(id, limit || 60)
  if (!messages.length) return text(`No messages found for "${session}". Call list_sessions to see what is open.`)
  return text(`# ${title || s?.title || id}\nfolder: ${s?.folder || '?'} · status: ${s?.status || 'ended'}\n\n` +
    messages.map((m) => `**${m.role === 'user' ? config.userName : 'Claude'}** (${m.time?.slice(0, 16).replace('T', ' ')}):\n${m.text}`).join('\n\n---\n\n'))
})

server.registerTool('search_sessions', {
  description: `Search all of ${config.userName}'s Claude Code transcripts on ${config.machineName} (open and ended) for a keyword or phrase. Every word must appear in a message. Returns the newest matching sessions with short snippets; use read_session with the sessionId to read one in full.`,
  inputSchema: { query: z.string().min(2).describe('keyword or phrase, e.g. "backup" or "deploy script"'), limit: z.number().int().min(1).max(25).optional().describe('max sessions (default 10)') },
}, async ({ query, limit }) => {
  seen()
  const r = searchSessions(query, limit || 10)
  return text(r.length ? r : `No session mentions "${query}".`)
})

server.registerTool('shared_sessions', {
  description: `Sessions ${config.userName} sent to Claude from Session Deck ("Send to Claude"), newest first. Start here when asked to review what was sent.`,
  inputSchema: {},
}, async () => {
  seen()
  let shared = []
  try { shared = JSON.parse(readFileSync(path.join(STATE, 'shared.json'), 'utf8')) } catch {}
  return text(shared.length ? shared : 'Nothing has been sent from Session Deck yet.')
})

seen()
await server.connect(new StdioServerTransport())
