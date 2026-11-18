// The bridge to the desktop pet: each Claude Code session writes how it is doing
// to %USERPROFILE%\.claude\mochi\sessions\<session>.json, and the desktop pet
// (desktop/mochi-desktop.ps1) reads every session's file once a second.

import type { EngineInterface } from 'claude-code'

import { desktopFramesJson } from './art'
import type { Mood } from './art'

type $ = EngineInterface

/** What one session tells the desktop pet. */
export type SessionReport = {
  v: 1
  /** The desktop app's id for the chat (`local_…`), which a claude:// link opens; null outside the app. */
  session: string | null
  /** The Claude Code session id. */
  cli: string
  /** The project folder's name, and its path. */
  project: string
  cwd: string
  mood: Mood
  /** What waits on the person, if anything. */
  alert: 'question' | 'permission' | null
  /** When the current alert began (epoch ms), 0 without one. */
  alertSince: number
  /** When the last turn started and finished (epoch ms). */
  startedAt: number
  finishedAt: number
  /** When the person last had this chat in front of them (epoch ms): its messages on screen, typing, a press. */
  seenAt?: number
  /** When this file was written: the pet drops a session it has not heard from in a while. */
  updated: number
  ended?: true
}

export type Desktop = {
  dir: string
  file: string
  session: string | null
  cli: string
  project: string
  cwd: string
}

const sep = (path: string) => (path.includes('\\') ? '\\' : '/')
const join = (...parts: string[]) => parts.join(sep(parts[0] ?? ''))
const baseName = (path: string) => path.replace(/[\\/]+$/, '').split(/[\\/]/).pop() || path

/** Works out where this session reports, and readies the shared folder. */
export async function openDesktop($: $): Promise<Desktop | undefined> {
  const home = (await $.env.get('USERPROFILE')) ?? (await $.env.get('HOME'))
  if (!home) return undefined
  const session = (await $.env.get('CLAUDE_CODE_HOST_SESSION_ID')) ?? null
  const cli = await $.session.id()
  const cwd = await $.session.cwd()
  const dir = join(home, '.claude', 'mochi')
  const name = (session ?? cli).replace(/[^A-Za-z0-9_-]/g, '_')
  const desktop: Desktop = { dir, file: join(dir, 'sessions', `${name}.json`), session, cli, project: baseName(cwd), cwd }

  // The art, for the desktop pet to draw; rewritten only when it changed.
  const frames = desktopFramesJson()
  const framesFile = join(dir, 'frames.json')
  const current = await $.fs.read(framesFile).catch(() => '')
  if (current !== frames) await $.fs.write(framesFile, frames)
  return desktop
}

/** Starts the desktop pet unless the person turned that off; the pet itself refuses a second copy. */
export async function launchDesktopPet($: $, desktop: Desktop) {
  const settings = await $.fs.read(join(desktop.dir, 'desktop.json')).catch(() => '')
  try {
    if (settings && JSON.parse(settings.replace(/^﻿/, '')).autoStart === false) return
  } catch {
    // Unreadable settings: start as by default.
  }
  const script = join($.plugin.root, 'desktop', 'mochi-desktop.ps1')
  const quoted = script.replace(/'/g, "''")
  await $.process.run(
    [
      'powershell.exe',
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      `Start-Process powershell.exe -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "' + '${quoted}' + '"')`,
    ],
    { timeoutMs: 20_000 },
  )
}

let lastWritten = ''
let lastWriteAt = 0

/** Writes this session's report when it changed, and at least every 10 s as a heartbeat. */
export async function report($: $, desktop: Desktop, now: number, fields: Omit<SessionReport, 'v' | 'session' | 'cli' | 'project' | 'cwd' | 'updated'>) {
  const body = JSON.stringify({ ...fields })
  if (body === lastWritten && now - lastWriteAt < 10_000 && !fields.ended) return
  const full: SessionReport = {
    v: 1,
    session: desktop.session,
    cli: desktop.cli,
    project: desktop.project,
    cwd: desktop.cwd,
    ...fields,
    updated: now,
  }
  await $.fs.write(desktop.file, JSON.stringify(full))
  lastWritten = body
  lastWriteAt = now
}
