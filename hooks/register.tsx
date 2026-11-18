import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { PetAlert, PetState } from '../types'
import { cellRows, SVG } from './art'
import type { Mood } from './art'

const PANE = 'pixel-pet'
const TITLE = 'Mochi'
/** Quiet time before Mochi dozes off. */
const SLEEP_MS = 90_000
/** How long Mochi celebrates a finished task. */
const HAPPY_MS = 5_000
/** Tools whose whole point is to ask the person something. */
const QUESTION_TOOLS = new Set(['AskUserQuestion', 'ExitPlanMode'])
/** Modes in which an `ask` verdict goes straight to the person. */
const ASKING_MODES = new Set(['default', 'acceptEdits', 'plan'])

const INITIAL: PetState = {
  busy: false,
  tools: 0,
  alerts: [],
  happyUntil: 0,
  lastActive: 0,
  asleep: false,
}
const pet = atom({ plugin: 'pixel-pet', key: 'pet' } as const, INITIAL, { shape: 'pet-1' })
const tick = atom({ plugin: 'pixel-pet', key: 'tick' } as const, 0)

type $ = EngineInterface

/** Calls the engine said `ask` for, newest last, so a permission prompt can be tied to its call. */
let pendingAsks: { id: string; tool: string }[] = []
/** The permission mode, as the classic hook inputs last reported it. */
let permissionMode: string | undefined

function moodOf(s: PetState, now: number): Mood {
  if (s.alerts.length > 0) return 'alert'
  if (s.happyUntil > now) return 'happy'
  if (s.busy || s.tools > 0) return 'working'
  if (s.asleep) return 'sleeping'
  return 'idle'
}

const CAPTION: Record<Mood, string> = {
  idle: 'Mochi is hanging out',
  working: 'Mochi is busy…',
  sleeping: 'Mochi is napping  z z z',
  happy: 'Mochi is happy!',
  alert: 'Claude has a question!',
}

async function wake($: $, patch: (s: PetState) => PetState = s => s) {
  const now = await $.clock.now()
  await update($, pet, s => ({ ...patch(s), asleep: false, lastActive: now }))
}

const NOTICE_KEY = 'pixel-pet-alert'
/** Whether a notification of ours is out, so it is sent once per alert and taken back once. */
let isNoticeOut = false

async function raise($: $, alert: PetAlert) {
  const wasQuiet = (await read($, pet)).alerts.length === 0
  await wake($, s =>
    s.alerts.some(a => a.id === alert.id && a.id !== '') ? s : { ...s, alerts: [...s.alerts, alert] },
  )
  if (wasQuiet && !isNoticeOut) {
    isNoticeOut = true
    try {
      await $.ui.notify(
        alert.kind === 'question'
          ? 'Claude has a question for you.'
          : `Claude needs your approval${alert.tool ? ` to use ${alert.tool}` : ''}.`,
        { title: 'Mochi', key: NOTICE_KEY },
      )
    } catch {
      // Notifications turned off or refused: Mochi's wave is still there.
    }
  }
}

/** Takes the notification back once nothing waits any more. */
async function quiet($: $) {
  if (!isNoticeOut || (await read($, pet)).alerts.length > 0) return
  isNoticeOut = false
  try {
    await $.ui.cancelNotify(NOTICE_KEY)
  } catch {
    // Nothing to take back.
  }
}

async function settle($: $, id: string) {
  pendingAsks = pendingAsks.filter(p => p.id !== id)
  await wake($, s => ({
    ...s,
    tools: Math.max(0, s.tools - 1),
    // A call that finished answers its own alert, and any alert we could not tie to a call.
    alerts: s.alerts.filter(a => a.id !== id && a.id !== ''),
  }))
  await quiet($)
}

async function petIt($: $) {
  const now = await $.clock.now()
  await update($, pet, s => ({ ...s, asleep: false, lastActive: now, happyUntil: now + 2_500 }))
}

async function goTo($: $, alert: PetAlert, viewingAgent: boolean) {
  if (viewingAgent) await $.ui.view({})
  // The waiting call's own row first, then Claude's latest message just above the question.
  const targets: [string, string | undefined, 'center' | 'end'][] = [
    ['call', alert.id || undefined, 'center'],
    ['latest message', lastAssistantId, 'end'],
  ]
  const refusals: string[] = []
  for (const [what, requestId, block] of targets) {
    if (!requestId) {
      refusals.push(`${what}: unknown`)
      continue
    }
    const moved = await $.ui.scroll({ to: { requestId }, block })
    if (!moved.deny) return
    refusals.push(`${what}${drawnIds.has(requestId) ? '' : ' (not drawn)'}: ${moved.deny}`)
  }
  $.ui.log(`pixel-pet could not scroll to the question: ${refusals.join('; ')}`, { to: 'debug' })
  // The desktop app lets no mod scroll its chat ("transcript not scrollable here"):
  // point the way instead. The question card sits at the bottom, by the prompt box.
  void $.ui.toast(
    alert.kind === 'question'
      ? "👇 Claude's question is waiting for you at the bottom of the chat."
      : '👇 Claude is waiting for your approval at the bottom of the chat.',
  )
}

/** The newest Claude message drawn, and the rows drawn lately, for jumping to a question. */
let lastAssistantId: string | undefined
const drawnIds = new Set<string>()
function remember(id: string) {
  drawnIds.add(id)
  if (drawnIds.size > 500) drawnIds.delete(drawnIds.values().next().value as string)
}

/** Sleep and the end of a celebration are time-based: check once a second. */
async function housekeeping($: $) {
  const s = await read($, pet)
  const now = await $.clock.now()
  const happyOver = s.happyUntil !== 0 && s.happyUntil <= now
  const sleepy =
    !s.asleep && !s.busy && s.tools === 0 && s.alerts.length === 0 && now - s.lastActive > SLEEP_MS
  if (happyOver || sleepy) {
    await update($, pet, cur => ({
      ...cur,
      happyUntil: happyOver ? 0 : cur.happyUntil,
      asleep: cur.asleep || sleepy,
    }))
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'pet', description: 'Show Mochi, your pixel pet, beside the chat' })
    void $.ui.open({ id: PANE, title: TITLE })
    // Fresh session: nothing is running or waiting yet.
    pendingAsks = []
    const now = await $.clock.now()
    await update($, pet, s => ({ ...s, busy: false, tools: 0, alerts: [], asleep: false, lastActive: now }))

    let n = 0
    $.clock.every(250, () => {
      n++
      void (async () => {
        if (n % 4 === 0) await housekeeping($)
        // Only the terminal needs frames pushed; SVG surfaces animate by themselves.
        if ((await $.session.surfaces()).includes('terminal')) await update($, tick, t => (t + 1) % 1_000_000)
      })()
    })
    return next(e)
  })

  on('command.run', { command: 'pet' }, async $ => {
    await $.ui.open({ id: PANE, title: TITLE })
    return { text: 'Mochi is beside the chat.' }
  })

  on('turn.start', async ($, e, next) => {
    if (!e.agentId) await wake($, s => ({ ...s, busy: true, happyUntil: 0 }))
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (!e.agentId) {
      const now = await $.clock.now()
      pendingAsks = []
      await update($, pet, s => ({
        ...s,
        busy: false,
        tools: 0,
        alerts: [],
        asleep: false,
        lastActive: now,
        happyUntil: e.reason === 'answer' ? now + HAPPY_MS : 0,
      }))
      await quiet($)
    }
    return done
  })

  on('tool.call', async ($, e, next) => {
    const id = e.tool_use_id ?? ''
    await wake($, s => ({ ...s, tools: s.tools + 1 }))
    if (!e.agentId && QUESTION_TOOLS.has(String(e.tool))) {
      await raise($, { id, tool: String(e.tool), kind: 'question' })
    }
    try {
      return await next(e)
    } finally {
      await settle($, id)
    }
  })

  // The engine's verdict on a call: `ask` means someone will be asked.
  on('tool.check', async ($, e, next) => {
    const verdict = await next(e)
    if (verdict.decision === 'ask' && e.tool_use_id && e.approver) {
      pendingAsks = [...pendingAsks.filter(p => p.id !== e.tool_use_id), { id: e.tool_use_id, tool: e.tool }]
      if (QUESTION_TOOLS.has(e.tool)) {
        await raise($, { id: e.tool_use_id, tool: e.tool, kind: 'question' })
      } else if (permissionMode && ASKING_MODES.has(permissionMode)) {
        await raise($, { id: e.tool_use_id, tool: e.tool, kind: 'permission' })
      }
    }
    return verdict
  })

  // Fired when the person is actually shown a permission prompt (after any classifier).
  on('classic.PermissionRequest', async ($, e, next) => {
    if (e.permission_mode) permissionMode = e.permission_mode
    const call = [...pendingAsks].reverse().find(p => p.tool === e.tool_name)
    await raise($, {
      id: call?.id ?? '',
      tool: e.tool_name,
      kind: QUESTION_TOOLS.has(e.tool_name) ? 'question' : 'permission',
    })
    return next(e)
  })

  on('classic.Notification', async ($, e, next) => {
    if (e.permission_mode) permissionMode = e.permission_mode
    if (e.notification_type === 'permission_prompt' || e.notification_type === 'elicitation_dialog') {
      const call = pendingAsks[pendingAsks.length - 1]
      await raise($, { id: call?.id ?? '', tool: call?.tool ?? '', kind: 'permission' })
    }
    return next(e)
  })

  on('classic.UserPromptSubmit', async ($, e, next) => {
    if (e.permission_mode) permissionMode = e.permission_mode
    return next(e)
  })

  // Watch (never change) what the chat draws, to know where a question sits.
  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    lastAssistantId = e.requestId
    remember(e.requestId)
    return next(e)
  })
  on('ui.render', { component: 'ToolUse' }, async ($, e, next) => {
    remember(e.requestId)
    return next(e)
  })
  on('ui.render', { component: 'AskUserQuestion' }, async ($, e, next) => {
    remember(e.requestId)
    return next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const s = await read($, pet)
    const now = await $.clock.now()
    const mood = moodOf(s, now)
    const alert = s.alerts[s.alerts.length - 1]
    const viewingAgent = Boolean(e.props.view?.agentId)
    const onPress = () => (alert ? goTo($, alert, viewingAgent) : petIt($))
    const label = alert ? '👉 Take me to the question' : '🐾 Pet Mochi'

    if (e.surface === 'terminal') {
      const { Box, Text, Button } = $.ui.resolve(e)
      const frame = await read($, tick)
      return (
        <Box flexDirection="column" alignItems="center">
          {alert && <Text bold>( Claude has a question! )</Text>}
          {cellRows(mood, frame).map(line => (
            <Text>
              {line.map(c =>
                c.fg && c.bg ? (
                  <Text color={c.fg} backgroundColor={c.bg}>{c.text}</Text>
                ) : c.fg ? (
                  <Text color={c.fg}>{c.text}</Text>
                ) : (
                  c.text
                ),
              )}
            </Text>
          ))}
          {!alert && <Text dimColor>{CAPTION[mood]}</Text>}
          <Button key={alert ? 'go' : 'pet'} variant={alert ? 'primary' : undefined} label={label} onPress={onPress} />
        </Box>
      )
    }

    const table = $.ui.resolve(e)
    const { Box, Text, Button } = table
    const art =
      'Svg' in table ? (
        <table.Svg source={SVG[mood]} alt={`Mochi the pixel pet: ${CAPTION[mood]}`} />
      ) : (
        <Text>{CAPTION[mood]}</Text>
      )
    if (e.props.placement === 'widget') {
      return (
        <Box flexDirection="column" alignItems="center">
          {art}
          {alert && <Button key="go" variant="primary" label={label} onPress={onPress} />}
        </Box>
      )
    }
    return (
      <Box flexDirection="column" alignItems="center">
        {art}
        {!alert && <Text dimColor>{CAPTION[mood]}</Text>}
        <Button key={alert ? 'go' : 'pet'} variant={alert ? 'primary' : undefined} label={label} onPress={onPress} />
      </Box>
    )
  })
}
