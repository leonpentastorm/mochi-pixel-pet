// The bridge to the desktop pet: each Claude Code session writes how it is doing
// to %USERPROFILE%\.claude\mochi\sessions\<session>.json, and the desktop pet
// (desktop/mochi-desktop.ps1) reads every session's file once a second.
//
// A session away from the pet's PC (a cloud session, or one on another machine)
// cannot reach that folder: given the link secret MOCHI_LINK, it sends a short,
// encrypted and signed report through ntfy.sh instead (see link.ts), and the
// desktop pet listens there.

import type { EngineInterface } from 'claude-code'

import { desktopFramesJson } from './art'
import type { Mood } from './art'
import { LINK_PATTERN, linkId, linkKeys, seal } from './link'
import type { LinkKeys } from './link'

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

/**
 * What a remote session sends through the link, kept to what the pet shows: no
 * paths, no session ids (`k` is a hash only the link's holders can match).
 */
export type LinkReport = {
  v: 1
  k: string
  p: string
  m: 'working' | 'idle'
  a: 'question' | 'permission' | null
  as: number
  s: number
  f: number
  u: number
  e?: 1
}

export type Desktop = {
  dir: string
  file: string
  session: string | null
  cli: string
  project: string
  cwd: string
  /** Set when this session reports through the cloud link instead of the local folder. */
  link?: LinkKeys
}

const sep = (path: string) => (path.includes('\\') ? '\\' : '/')
const join = (...parts: string[]) => parts.join(sep(parts[0] ?? ''))
const baseName = (path: string) => path.replace(/[\\/]+$/, '').split(/[\\/]/).pop() || path

/**
 * The link this session reports through, if it runs away from the pet's PC: a cloud
 * session (CLAUDE_CODE_REMOTE=true), or any session with MOCHI_RELAY=1, given
 * MOCHI_LINK, the secret the desktop pet made.
 */
export async function linkOf($: $): Promise<LinkKeys | undefined> {
  const remote = (await $.env.get('CLAUDE_CODE_REMOTE')) === 'true' || (await $.env.get('MOCHI_RELAY')) === '1'
  if (!remote) return undefined
  const secret = (await $.env.get('MOCHI_LINK'))?.trim()
  if (!secret || !LINK_PATTERN.test(secret)) return undefined
  return linkKeys(secret)
}

/** Works out where this session reports, and readies the shared folder. */
export async function openDesktop($: $): Promise<Desktop | undefined> {
  const link = await linkOf($)
  const home = (await $.env.get('USERPROFILE')) ?? (await $.env.get('HOME')) ?? ''
  if (!home && !link) return undefined
  const session = (await $.env.get('CLAUDE_CODE_HOST_SESSION_ID')) ?? null
  const cli = await $.session.id()
  const cwd = await $.session.cwd()
  const dir = join(home, '.claude', 'mochi')
  const name = (session ?? cli).replace(/[^A-Za-z0-9_-]/g, '_')
  const desktop: Desktop = { dir, file: join(dir, 'sessions', `${name}.json`), session, cli, project: baseName(cwd), cwd }
  if (link) return { ...desktop, link }

  // The art, for the desktop pet to draw; rewritten only when it changed.
  const frames = desktopFramesJson()
  const framesFile = join(dir, 'frames.json')
  const current = await $.fs.read(framesFile).catch(() => '')
  if (current !== frames) await $.fs.write(framesFile, frames)
  return desktop
}

/** Starts the desktop pet unless the person turned that off; the pet itself refuses a second copy. */
export async function launchDesktopPet($: $, desktop: Desktop) {
  // A linked session runs away from the pet's PC: there is no pet to start here.
  if (desktop.link) return
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

/**
 * ntfy.sh lets an address without an account send about 250 messages a day, a
 * new one every 5 s: a linked session sends only when what the pet shows changes,
 * no sooner than 5 s after the last, and otherwise a heartbeat every 10 minutes.
 * The pet forgets a remote session silent for 25 minutes.
 */
export const LINK_HEARTBEAT_MS = 10 * 60_000
export const LINK_MIN_GAP_MS = 5_000
const LINK_RETRY_MS = 60_000

let lastWritten = ''
let lastWriteAt = -Infinity
let sending = false
let linkRetryAt = 0

/** Posts one sealed report to the link's ntfy topic; true once ntfy took it. */
async function sendLink($: $, keys: LinkKeys, message: LinkReport): Promise<boolean> {
  try {
    const res = await $.http.fetch(`https://ntfy.sh/${keys.topic}`, {
      method: 'POST',
      headers: { Cache: 'no', Firebase: 'no', 'Content-Type': 'text/plain' },
      body: await seal(keys, JSON.stringify(message)),
    })
    return res.ok
  } catch {
    return false
  }
}

/**
 * Writes this session's report when it changed, and as a heartbeat: every 10 s to
 * the local folder; through the link, as LINK_HEARTBEAT_MS and LINK_MIN_GAP_MS say.
 */
export async function report($: $, desktop: Desktop, now: number, fields: Omit<SessionReport, 'v' | 'session' | 'cli' | 'project' | 'cwd' | 'updated'>) {
  const keys = desktop.link
  if (keys) {
    // Only what the pet shows: asleep, cheering and idle all read as idle from afar.
    const coarse = {
      m: fields.mood === 'working' ? 'working' : 'idle',
      a: fields.alert,
      as: fields.alertSince,
      s: fields.startedAt,
      f: fields.finishedAt,
      e: fields.ended ? 1 : undefined,
    } as const
    const body = JSON.stringify(coarse)
    if (!fields.ended) {
      if (body === lastWritten && now - lastWriteAt < LINK_HEARTBEAT_MS) return
      if (now - lastWriteAt < LINK_MIN_GAP_MS || now < linkRetryAt) return
    }
    // One send at a time: the 250 ms ticks overlap while one is on its way.
    if (sending && !fields.ended) return
    sending = true
    try {
      const message: LinkReport = { v: 1, k: await linkId(keys, desktop.cli), p: desktop.project.slice(0, 40), ...coarse, u: now }
      if (!(await sendLink($, keys, message))) {
        linkRetryAt = now + LINK_RETRY_MS
        return
      }
      lastWritten = body
      lastWriteAt = now
    } finally {
      sending = false
    }
    return
  }

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
