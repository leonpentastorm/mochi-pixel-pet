import { expect, mock, test } from 'claude-code/testing'

import { SVG } from '../hooks/art'

const PANE = {
  plugin: 'pixel-pet',
  component: 'Pane',
  requestId: 'pixel-pet',
  props: {
    title: 'Mochi',
    isFocused: false,
    bodyColumns: 40,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 30 },
    view: {},
  },
} as const

test('every mood has an SVG within the element limit', async () => {
  for (const [mood, svg] of Object.entries(SVG)) {
    expect(svg.length).toBeLessThan(131072)
  }
})

test('Mochi waves while a question waits, then goes back to normal', async ($, on) => {
  const clock = mock.clock(on)
  on('session.surfaces', () => ({ value: ['desktop'] }))
  on('command.register', () => ({ value: { command: 'pet' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  const notified: string[] = []
  const cancelled: string[] = []
  on('ui.notify', (_, e) => {
    notified.push(e.text)
    return { value: { isSent: true, channel: 'client' } }
  })
  on('ui.cancelNotify', (_, e) => {
    cancelled.push(String(e.key))
    return { value: { isSent: true } }
  })

  let seenWhileAsking: string | undefined
  on('tool.call', async (_, e) => {
    if (String(e.tool) === 'AskUserQuestion') {
      const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
      seenWhileAsking = (await ui.find({ key: 'go' }))?.text
      await ui.unmount()
    }
    return { result: {} }
  })

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ key: 'pet' }))?.text).toContain('Pet Mochi')
    await ui.unmount()
  }

  await $.tool.call({ tool: 'AskUserQuestion', questions: [] } as never)
  expect(seenWhileAsking).toContain('Take me to the question')
  expect(notified).toEqual(['Claude has a question for you.'])
  expect(cancelled).toEqual(['pixel-pet-alert'])

  const after = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(await after.find({ key: 'go' })).toBeUndefined()
  await after.press({ key: 'pet' })
  expect((await after.find({ type: 'Text', text: /happy/ }))?.text).toBe('Mochi is happy!')

  // A quiet minute and a half later, Mochi has dozed off.
  await clock.advance(95_000)
  expect((await after.find({ type: 'Text', text: /napping/ }))?.text).toContain('Mochi is napping')
  await after.unmount()
})
