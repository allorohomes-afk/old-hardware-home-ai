// Personal settings live OUTSIDE the code, in ~/.config/session-deck/config.json (see config.example.json).
// Everything has a safe default, so the deck runs with no config: features that need one (the Hive copy,
// the notes log) just say they aren't set up.
import { readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import path from 'node:path'

const FILE = process.env.SESSION_DECK_CONFIG || path.join(homedir(), '.config/session-deck/config.json')
let user = {}
try { user = JSON.parse(readFileSync(FILE, 'utf8')) } catch {}

export const config = {
  userName: user.userName || 'You',
  machineName: user.machineName || 'this Mac',
  hive: user.hive?.ssh ? {
    ssh: user.hive.ssh,
    sshOptions: user.hive.sshOptions || [],
    mountCheck: user.hive.mountCheck || null,
    dest: user.hive.dest || 'session-deck/claude-sessions',
    label: user.hive.label || 'the Hive',
  } : null,
  notes: user.notes?.keychainService && user.notes?.keychainAccount ? {
    url: user.notes.url || 'https://127.0.0.1:27124',
    keychainService: user.notes.keychainService,
    keychainAccount: user.notes.keychainAccount,
    runLogFolder: user.notes.runLogFolder || 'Runs',
    signature: user.notes.signature || '',
  } : null,
  summaryModel: process.env.DECK_SUMMARY_MODEL || user.summaryModel || 'qwen2.5:7b',
  file: FILE,
}
