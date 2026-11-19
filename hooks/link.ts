// The cloud link: how a session away from the pet's PC (a cloud session, or one on
// another machine) reaches the desktop pet without any account or server of yours.
//
// One secret, MOCHI_LINK (made by the desktop pet's "Connect cloud sessions..."),
// is shared by the pet and the remote sessions. From it come three things no one
// else can work out:
//   topic   the ntfy.sh channel the messages go through
//   enc     the key that encrypts each message (SHA-256 in counter mode)
//   mac     the key that signs each message (HMAC-SHA256, encrypt-then-MAC)
// ntfy.sh only ever sees the topic and opaque bytes; it keeps nothing (Cache: no)
// and forwards nothing (Firebase: no). The pet drops anything whose signature
// does not check out, or that is old or replayed.
//
// The same construction is in desktop/mochi-desktop.ps1; tests check both agree.

const te = new TextEncoder()

export async function sha256(...parts: Uint8Array[]): Promise<Uint8Array> {
  const total = parts.reduce((n, p) => n + p.length, 0)
  const all = new Uint8Array(total)
  let at = 0
  for (const p of parts) {
    all.set(p, at)
    at += p.length
  }
  return new Uint8Array(await crypto.subtle.digest('SHA-256', all))
}

/** HMAC-SHA256 (RFC 2104), built on the runtime's SHA-256. */
export async function hmac(key: Uint8Array, message: Uint8Array): Promise<Uint8Array> {
  const k = key.length > 64 ? await sha256(key) : key
  const block = new Uint8Array(64)
  block.set(k)
  const ipad = block.map(b => b ^ 0x36)
  const opad = block.map(b => b ^ 0x5c)
  return sha256(opad, await sha256(ipad, message))
}

export const hex = (b: Uint8Array) => Array.from(b, x => x.toString(16).padStart(2, '0')).join('')

export function base64url(b: Uint8Array): string {
  let s = ''
  for (const x of b) s += String.fromCharCode(x)
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

export type LinkKeys = { topic: string; enc: Uint8Array; mac: Uint8Array }

/** A link secret: 32 random bytes, base64url (43 characters). */
export const LINK_PATTERN = /^[A-Za-z0-9_-]{43}$/

export async function linkKeys(secret: string): Promise<LinkKeys> {
  const topic = 'mochi_' + hex(await sha256(te.encode('mochi-topic-v1:' + secret))).slice(0, 40)
  const enc = await sha256(te.encode('mochi-enc-v1:' + secret))
  const mac = await sha256(te.encode('mochi-mac-v1:' + secret))
  return { topic, enc, mac }
}

/** A short id for a session that says nothing about it outside the link. */
export async function linkId(keys: LinkKeys, cli: string): Promise<string> {
  return hex(await sha256(keys.mac, te.encode(cli))).slice(0, 16)
}

/** Encrypts and signs: base64url(nonce[16] ‖ ciphertext ‖ tag[32]). */
export async function seal(keys: LinkKeys, plaintext: string, nonce = crypto.getRandomValues(new Uint8Array(16))): Promise<string> {
  const pt = te.encode(plaintext)
  const ct = new Uint8Array(pt.length)
  for (let i = 0, block = 0; i < pt.length; block++) {
    const counter = new Uint8Array([block >>> 24, (block >>> 16) & 255, (block >>> 8) & 255, block & 255])
    const ks = await sha256(keys.enc, nonce, counter)
    for (let j = 0; j < 32 && i < pt.length; j++, i++) ct[i] = pt[i]! ^ ks[j]!
  }
  const tag = await hmac(keys.mac, new Uint8Array([...te.encode('mochi-v1'), ...nonce, ...ct]))
  return base64url(new Uint8Array([...nonce, ...ct, ...tag]))
}
