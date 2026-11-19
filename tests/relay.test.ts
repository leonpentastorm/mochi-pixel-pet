import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

import { hex, hmac, linkKeys, seal } from '../hooks/link'

const te = new TextEncoder()

test('HMAC-SHA256 matches RFC 4231 test case 2', async () => {
  const mac = await hmac(te.encode('Jefe'), te.encode('what do ya want for nothing?'))
  expect(hex(mac)).toBe('5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843')
})

test('sealing matches the desktop pet byte for byte (tests/link-desktop.ps1 prints the same)', async () => {
  const keys = await linkKeys('A'.repeat(43))
  expect(keys.topic).toBe('mochi_6c2fa00d8bcdb9b8979dfc887e2d784fee352ba8')
  const plain = '{"v":1,"k":"0123456789abcdef","p":"my-repo","m":"working","a":null,"as":0,"s":1000,"f":0,"u":2000}'
  const nonce = new Uint8Array(Array.from({ length: 16 }, (_, i) => i))
  expect(await seal(keys, plain, nonce)).toBe(
    'AAECAwQFBgcICQoLDA0OD48mCS9FcWKlD5TrQr3NsSp4BFTvIU_AZ-PHNKp6Tu-1bHDu9E1ESU5Kcl4plhzCJ4shsWP-UF7W0mV6rLs7uOxWwjAJ1rkbGNL1l6VFsSd3R4wNfqiZhm3WeLTHIrwyAOfygJU2z1o3R9Do3_b8V0lwc59JerQhfL3UW8n0zOlewEo',
  )
})

const SECRET = 'A'.repeat(43)

function setup(on: On, env: Record<string, string>) {
  const clock = mock.clock(on)
  on('session.surfaces', () => ({ value: ['desktop'] }))
  on('command.register', () => ({ value: { command: 'pet' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  mock.env(on, env)
  on('session.id', () => ({ value: 'cli-secret-id' }))
  on('session.cwd', () => ({ value: '/home/user/secret-path/my-repo' }))
  const written: string[] = []
  on('fs.write', (_, e) => {
    written.push(String(e.path))
    return { value: undefined }
  })
  const sent: { url: string; method?: string; headers: Record<string, string>; body: string }[] = []
  on('http.fetch', (_, e) => {
    sent.push({ url: e.url, method: e.init?.method, headers: { ...e.init?.headers }, body: String(e.init?.body ?? '') })
    return { value: { status: 200, ok: true, headers: {}, text: '{}' } }
  })
  let launched = false
  on('process.run', () => {
    launched = true
    return { deny: 'no processes in tests' }
  })
  return { clock, written, sent, launched: () => launched }
}

test('a cloud session sends sealed reports through ntfy, rarely, and nothing in the clear', async ($, on) => {
  const { clock, written, sent, launched } = setup(on, { HOME: '/home/user', CLAUDE_CODE_REMOTE: 'true', MOCHI_LINK: SECRET })
  await $.session.start({ cwd: '/home/user/secret-path/my-repo', surface: 'desktop', isInteractive: true })
  await clock.advance(1_000)

  expect(launched()).toBe(false)
  expect(written).toEqual([])
  expect(sent.length).toBe(1)
  const first = sent[0]!
  const { topic } = await linkKeys(SECRET)
  expect(first.url).toBe(`https://ntfy.sh/${topic}`)
  expect(first.method).toBe('POST')
  expect(first.headers.Cache).toBe('no')
  expect(first.headers.Firebase).toBe('no')
  expect(first.body).toMatch(/^[A-Za-z0-9_-]+$/)
  for (const secret of ['my-repo', 'secret-path', 'cli-secret-id', SECRET]) expect(first.body.includes(secret)).toBe(false)

  // Unchanged: nothing more until the 10-minute heartbeat.
  await clock.advance(5 * 60_000)
  expect(sent.length).toBe(1)
  await clock.advance(6 * 60_000)
  expect(sent.length).toBe(2)
})

test('a session on the pet’s own PC never touches the network', async ($, on) => {
  const { clock, sent } = setup(on, { HOME: '/home/user', MOCHI_LINK: SECRET })
  await $.session.start({ cwd: '/home/user/my-repo', surface: 'desktop', isInteractive: true })
  await clock.advance(30_000)
  expect(sent).toEqual([])
})

test('a remote session with a malformed link key stays quiet', async ($, on) => {
  const { clock, sent } = setup(on, { HOME: '/home/user', CLAUDE_CODE_REMOTE: 'true', MOCHI_LINK: 'too-short' })
  await $.session.start({ cwd: '/home/user/my-repo', surface: 'desktop', isInteractive: true })
  await clock.advance(30_000)
  expect(sent).toEqual([])
})
