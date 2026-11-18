// Mochi's pixel art: sprite layers composed into frames, then emitted as an
// animated SVG (CSS keyframes, no script) per mood, plus half-block text rows
// for surfaces that draw no SVG (the terminal).

export type Mood = 'idle' | 'working' | 'sleeping' | 'happy' | 'alert'

const PAL: Record<string, string> = {
  O: '#2d1e3a', // outline
  E: '#2d1e3a', // eyes / mouth line
  B: '#ffc98b', // body
  S: '#f0a35e', // body shade
  I: '#ff9fb2', // inner ear
  W: '#ffffff', // eye shine, bubble
  P: '#ff8fa3', // cheeks
  M: '#d6405c', // open mouth
  G: '#a7b0c2', // laptop lid
  D: '#5d6577', // laptop base
  L: '#7ee0a1', // laptop light on
  l: '#4b8f66', // laptop light off
  Y: '#ffd166', // sparkle, lit thought dot
  y: '#b9b2c9', // dim thought dot
  Z: '#7aa2f7', // sleepy z
  H: '#2d1e3a33', // floor shadow
}

/** Canvas size in pixels, and where the pet's body sits on it. */
const CW = 56
const CH = 46
const OX = 20
const OY = 25

const BODY = [
  '..OO........OO..',
  '.OBBO......OBBO.',
  '.OBIBOOOOOOBIBO.',
  'OBBBBBBBBBBBBBBO',
  'OBBBBBBBBBBBBBBO',
  'OBBBBBBBBBBBBBBO',
  'OBBBBBBBBBBBBBBO',
  'OBBBBBBBBBBBBBBO',
  'OBBBBBBBBBBBBBBO',
  'OBBBBBBBBBBBBBBO',
  'OSBBBBBBBBBBBBSO',
  '.OSSBBBBBBBBSSO.',
  '..OOOOOOOOOOOO..',
]
const FEET = ['...OBBO..OBBO...', '...OOOO..OOOO...']

type Dot = readonly [number, number, string]
type Eyes = 'open' | 'closed' | 'happy' | 'wide' | 'down' | 'sleep'
type Mouth = 'smile' | 'open' | 'flat' | 'snore'
type Arm = 'waveA' | 'waveB' | 'leftUp'

const EYES: Record<Eyes, Dot[]> = {
  open: [[5, 5, 'E'], [5, 6, 'E'], [10, 5, 'E'], [10, 6, 'E']],
  closed: [[4, 6, 'E'], [5, 6, 'E'], [10, 6, 'E'], [11, 6, 'E']],
  happy: [[3, 6, 'E'], [4, 5, 'E'], [5, 6, 'E'], [10, 6, 'E'], [11, 5, 'E'], [12, 6, 'E']],
  wide: [
    [4, 4, 'E'], [5, 4, 'E'], [4, 5, 'E'], [5, 5, 'E'], [4, 6, 'E'], [5, 6, 'E'],
    [10, 4, 'E'], [11, 4, 'E'], [10, 5, 'E'], [11, 5, 'E'], [10, 6, 'E'], [11, 6, 'E'],
  ],
  down: [[4, 6, 'E'], [5, 6, 'E'], [4, 7, 'E'], [5, 7, 'E'], [10, 6, 'E'], [11, 6, 'E'], [10, 7, 'E'], [11, 7, 'E']],
  sleep: [[3, 5, 'E'], [4, 6, 'E'], [5, 6, 'E'], [6, 5, 'E'], [9, 5, 'E'], [10, 6, 'E'], [11, 6, 'E'], [12, 5, 'E']],
}
const MOUTH: Record<Mouth, Dot[]> = {
  smile: [[6, 7, 'E'], [9, 7, 'E'], [7, 8, 'E'], [8, 8, 'E']],
  open: [[6, 7, 'E'], [7, 7, 'E'], [8, 7, 'E'], [9, 7, 'E'], [6, 8, 'E'], [7, 8, 'M'], [8, 8, 'M'], [9, 8, 'E'], [7, 9, 'E'], [8, 9, 'E']],
  flat: [[7, 8, 'E'], [8, 8, 'E']],
  snore: [[7, 8, 'M']],
}
const CHEEKS: Dot[] = [[2, 7, 'P'], [3, 7, 'P'], [12, 7, 'P'], [13, 7, 'P']]

const ARMS: Record<Arm, { x: number; y: number; rows: string[] }> = {
  waveA: { x: 15, y: 1, rows: ['.OO.', 'OBBO', 'OBBO', '.OBO', '.OBO', '.OO.'] },
  waveB: { x: 15, y: 0, rows: ['....OO', '...OBBO', '...OBBO', '..OBBO', '.OBBO', '.OBO', '.OO'] },
  leftUp: { x: -3, y: 1, rows: ['.OO.', 'OBBO', 'OBBO', 'OBO.', 'OBO.', '.OO.'] },
}
const LID = ['OOOOOOOOOO', 'OGGGxxGGGO', 'OGGGGGGGGO', 'OOOOOOOOOO']
const BASE = ['ODDDDDDDDDDDDO', 'OOOOOOOOOOOOOO']
const PAW = ['OBBO', '.OO.']
const SPARKLE = ['.Y.', 'YWY', '.Y.']
const SPARKLE_AT: [number, number][] = [[-8, 3], [20, -1], [-6, 10], [20, 9]]

type Pose = {
  ms: number
  eyes: Eyes
  mouth: Mouth
  /** Whole pet up (negative) or down, for jumps. */
  dy?: number
  /** Body and face down this much over still feet: breathing, crouching. */
  breath?: number
  arms?: Arm[]
  laptop?: { leftPawUp: boolean; light: boolean; dot: number }
  sparkles?: boolean
  /** Floating Z's at this step (0-7), for pictures that animate frame by frame. */
  zs?: number
}

type Grid = Map<string, string>

function stamp(g: Grid, rows: readonly string[], x0: number, y0: number, swap?: Record<string, string>) {
  rows.forEach((row, dy) => {
    for (let dx = 0; dx < row.length; dx++) {
      const c = row[dx]
      if (c !== undefined && c !== '.') g.set(`${x0 + dx},${y0 + dy}`, swap?.[c] ?? c)
    }
  })
}
function dots(g: Grid, list: readonly Dot[], x0: number, y0: number) {
  for (const [x, y, c] of list) g.set(`${x0 + x},${y0 + y}`, c)
}

function compose(p: Pose): Grid {
  const g: Grid = new Map()
  const dy = p.dy ?? 0
  const lift = Math.max(0, -dy)
  // Floor shadow, smaller while the pet is in the air.
  const k = lift >= 4 ? 3 : lift >= 2 ? 2 : lift > 0 ? 1 : 0
  for (let x = OX + 2 + k; x <= OX + 13 - k; x++) g.set(`${x},${OY + 15}`, 'H')

  const fx = OX
  const fy = OY + dy
  const by = fy + (p.breath ?? 0)
  stamp(g, BODY, fx, by)
  stamp(g, FEET, fx, fy + 13)
  dots(g, CHEEKS, fx, by)
  dots(g, EYES[p.eyes], fx, by)
  dots(g, MOUTH[p.mouth], fx, by)
  for (const arm of p.arms ?? []) stamp(g, ARMS[arm].rows, fx + ARMS[arm].x, by + ARMS[arm].y)
  if (p.laptop) {
    stamp(g, LID, fx + 3, fy + 9, { x: p.laptop.light ? 'L' : 'l' })
    stamp(g, BASE, fx + 1, fy + 13)
    stamp(g, PAW, fx + 1, fy + (p.laptop.leftPawUp ? 11 : 12))
    stamp(g, PAW, fx + 11, fy + (p.laptop.leftPawUp ? 12 : 11))
    ;[4, 7, 10].forEach((x, i) => stamp(g, ['cc', 'cc'], fx + x, fy - 4, { c: i === p.laptop!.dot ? 'Y' : 'y' }))
  }
  if (p.sparkles) for (const [x, y] of SPARKLE_AT) stamp(g, SPARKLE, fx + x, fy + y)
  if (p.zs !== undefined) {
    // Two Z's drifting up and to the right, half a cycle apart; each vanishes at its top.
    for (const [shape, x, y, offset] of [[Z_SMALL, 15, -1, 0], [Z_BIG, 16, -3, 4]] as const) {
      const step = (p.zs + offset) % 8
      if (step < 7) stamp(g, shape, fx + x + Math.floor(step / 2), fy + y - Math.floor(step * 1.6))
    }
  }
  return g
}

/** SVG path data per fill color, horizontal runs merged. */
function paths(g: Grid): string {
  const byColor = new Map<string, Map<number, number[]>>()
  for (const [key, c] of g) {
    const [x, y] = key.split(',').map(Number) as [number, number]
    if (x < 0 || y < 0 || x >= CW || y >= CH) continue
    const fill = PAL[c] ?? c
    let rows = byColor.get(fill)
    if (!rows) byColor.set(fill, (rows = new Map()))
    let xs = rows.get(y)
    if (!xs) rows.set(y, (xs = []))
    xs.push(x)
  }
  let out = ''
  for (const [fill, rows] of byColor) {
    let d = ''
    for (const [y, xs] of rows) {
      xs.sort((a, b) => a - b)
      let start = xs[0]!
      let prev = start
      for (let i = 1; i <= xs.length; i++) {
        const x = xs[i]
        if (x === prev + 1) {
          prev = x
          continue
        }
        d += `M${start} ${y}h${prev - start + 1}v1h-${prev - start + 1}z`
        if (x !== undefined) start = prev = x
      }
    }
    out += `<path fill="${fill}" d="${d}"/>`
  }
  return out
}

const POSES: Record<Mood, Pose[]> = (() => {
  const idle = { eyes: 'open', mouth: 'smile' } as const
  const work = { eyes: 'down', mouth: 'flat' } as const
  const zzz = { eyes: 'sleep', mouth: 'snore' } as const
  const yay = { eyes: 'happy', mouth: 'open' } as const
  const hey = { eyes: 'wide', mouth: 'open' } as const
  const both: Arm[] = ['leftUp', 'waveA']
  return {
    idle: [
      { ...idle, ms: 800 },
      { ...idle, breath: 1, ms: 800 },
      { ...idle, ms: 700 },
      { ...idle, eyes: 'closed', ms: 130 },
      { ...idle, ms: 500 },
      { ...idle, breath: 1, ms: 800 },
      { ...idle, ms: 800 },
      { ...idle, breath: 1, ms: 800 },
    ],
    working: [0, 1, 2, 3, 4, 5].map(i => ({
      ...work,
      ms: 150,
      breath: i % 3 === 0 ? 1 : 0,
      laptop: { leftPawUp: i % 2 === 0, light: i % 3 !== 2, dot: Math.floor(i / 2) },
    })),
    sleeping: [
      { ...zzz, breath: 1, ms: 1200 },
      { ...zzz, breath: 2, ms: 1200 },
    ],
    happy: [
      { ...yay, breath: 1, ms: 120 },
      { ...yay, dy: -3, arms: both, ms: 110 },
      { ...yay, dy: -5, arms: both, sparkles: true, ms: 220 },
      { ...yay, dy: -3, arms: both, sparkles: true, ms: 110 },
      { ...yay, breath: 1, ms: 120 },
      { ...yay, ms: 420 },
    ],
    alert: [
      { ...hey, arms: ['waveA'], ms: 170 },
      { ...hey, dy: -2, arms: ['waveB'], ms: 170 },
      { ...hey, dy: -3, arms: ['waveA'], ms: 170 },
      { ...hey, dy: -2, arms: ['waveB'], ms: 170 },
    ],
  }
})()

const Z_SMALL = ['ZZZZ', '..Z.', '.Z..', 'ZZZZ']
const Z_BIG = ['ZZZZZ', '...Z.', '..Z..', '.Z...', 'ZZZZZ']

function bubble(): string {
  const g: Grid = new Map()
  const x0 = 2
  const x1 = CW - 3
  const top = 1
  const bottom = 19
  for (let y = top; y <= bottom; y++) {
    const inset = y === top || y === bottom ? 2 : y === top + 1 || y === bottom - 1 ? 1 : 0
    for (let x = x0 + inset; x <= x1 - inset; x++) {
      const edge = y === top || y === bottom || x === x0 + inset || x === x1 - inset
      g.set(`${x},${y}`, edge ? 'O' : 'W')
    }
  }
  // The tail, pointing down at the pet's head.
  const cx = OX + 8
  for (const x of [cx - 1, cx, cx + 1]) g.set(`${x},${bottom}`, 'W')
  g.set(`${cx - 1},${bottom + 1}`, 'O')
  g.set(`${cx},${bottom + 1}`, 'W')
  g.set(`${cx + 1},${bottom + 1}`, 'O')
  g.set(`${cx},${bottom + 2}`, 'O')
  const text = (y: number, length: number, words: string) =>
    `<text x="${CW / 2}" y="${y}" text-anchor="middle" font-family="Consolas,monospace" font-weight="700" ` +
    `font-size="6.5" textLength="${length}" lengthAdjust="spacingAndGlyphs" fill="${PAL.O}">${words}</text>`
  return `<g class="bb">${paths(g)}${text(9, 36, 'Claude has')}${text(16.5, 42, 'a question!')}</g>`
}

const pct = (n: number) => `${Math.round(n * 10000) / 100}%`

function svgFor(mood: Mood): string {
  const poses = POSES[mood]
  const total = poses.reduce((n, p) => n + p.ms, 0)
  let css = `.f{opacity:0;animation-duration:${total}ms;animation-iteration-count:infinite;animation-timing-function:step-end}`
  let body = ''
  let t = 0
  poses.forEach((p, i) => {
    const a = t / total
    t += p.ms
    const b = t / total
    if (poses.length === 1) {
      body += `<g>${paths(compose(p))}</g>`
      return
    }
    const frames =
      a === 0
        ? `0%{opacity:1}${pct(b)}{opacity:0}100%{opacity:0}`
        : b >= 1
          ? `0%{opacity:0}${pct(a)}{opacity:1}100%{opacity:1}`
          : `0%{opacity:0}${pct(a)}{opacity:1}${pct(b)}{opacity:0}100%{opacity:0}`
    css += `.f${i}{animation-name:k${i}}@keyframes k${i}{${frames}}`
    body += `<g class="f f${i}">${paths(compose(p))}</g>`
  })
  if (mood === 'sleeping') {
    css +=
      '@keyframes zf{0%{transform:translate(0px,0px);opacity:0}15%{opacity:1}70%{opacity:1}100%{transform:translate(6px,-14px);opacity:0}}' +
      '.z{animation:zf 3s steps(8,end) infinite;opacity:0}.z2{animation-delay:-1.5s}'
    const z1: Grid = new Map()
    stamp(z1, Z_SMALL, OX + 15, OY - 1)
    const z2: Grid = new Map()
    stamp(z2, Z_BIG, OX + 16, OY - 3)
    body += `<g class="z">${paths(z1)}</g><g class="z z2">${paths(z2)}</g>`
  }
  if (mood === 'alert') {
    css += '@keyframes bb{0%{transform:translate(0px,0px)}50%{transform:translate(0px,-1px)}}.bb{animation:bb 680ms step-end infinite}'
    body = bubble() + body
  }
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${CW} ${CH}" width="${CW * 5}" height="${CH * 5}" shape-rendering="crispEdges">` +
    `<style>${css}</style>${body}</svg>`
  )
}

export const SVG: Record<Mood, string> = {
  idle: svgFor('idle'),
  working: svgFor('working'),
  sleeping: svgFor('sleeping'),
  happy: svgFor('happy'),
  alert: svgFor('alert'),
}

/** The poses the desktop pet steps through: as in the chat, with the Z's drawn into the frames. */
function desktopPoses(mood: Mood): Pose[] {
  if (mood !== 'sleeping') return POSES[mood]
  const base = POSES.sleeping[0]!
  return [0, 1, 2, 3, 4, 5, 6, 7].map(i => ({ ...base, ms: 375, breath: i < 4 ? 1 : 2, zs: i }))
}

/**
 * Every frame of every mood as pixel rows, for the desktop pet program: one
 * character per pixel ('.' clear), each character a color in `palette` written
 * #AARRGGBB. Characters are digits and capitals only, so a case-blind reader
 * cannot mix two of them up.
 */
export function desktopFramesJson(): string {
  const keys = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
  const charOf = new Map<string, string>()
  const palette: Record<string, string> = {}
  const toArgb = (hex: string) => {
    const h = hex.replace('#', '')
    return `#${h.length === 8 ? h.slice(6) : 'ff'}${h.slice(0, 6)}`.toUpperCase()
  }
  const moods: Record<string, { ms: number; rows: string[] }[]> = {}
  for (const mood of ['idle', 'working', 'sleeping', 'happy', 'alert'] as const) {
    moods[mood] = desktopPoses(mood).map(p => {
      const g = compose(p)
      const rows: string[] = []
      for (let y = 0; y < CH; y++) {
        let row = ''
        for (let x = 0; x < CW; x++) {
          const c = g.get(`${x},${y}`)
          if (c === undefined) {
            row += '.'
            continue
          }
          const argb = toArgb(PAL[c] ?? c)
          let ch = charOf.get(argb)
          if (ch === undefined) {
            ch = keys[charOf.size] ?? '.'
            charOf.set(argb, ch)
            palette[ch] = argb
          }
          row += ch
        }
        rows.push(row)
      }
      return { ms: p.ms, rows }
    })
  }
  return JSON.stringify({ version: 1, width: CW, height: CH, palette, moods })
}

/** One run of half-block cells sharing colors, for the terminal. */
export type Cell = { text: string; fg?: string; bg?: string }

/** The pet's region as half-block rows: two pixels per character cell. */
export function cellRows(mood: Mood, frame: number): Cell[][] {
  const poses = POSES[mood]
  const g = compose(poses[frame % poses.length]!)
  const x0 = OX - 9
  const x1 = OX + 23
  const y0 = OY - 7
  const y1 = OY + 16
  const lines: Cell[][] = []
  for (let y = y0; y < y1; y += 2) {
    const line: Cell[] = []
    for (let x = x0; x < x1; x++) {
      const top = solid(g.get(`${x},${y}`))
      const bot = solid(g.get(`${x},${y + 1}`))
      const cell: Cell = top
        ? bot
          ? { text: '▀', fg: top, bg: bot }
          : { text: '▀', fg: top }
        : bot
          ? { text: '▄', fg: bot }
          : { text: ' ' }
      const last = line[line.length - 1]
      if (last && last.fg === cell.fg && last.bg === cell.bg && last.text[0] === cell.text) last.text += cell.text
      else line.push(cell)
    }
    lines.push(line)
  }
  return lines
}

/** Terminal cells take opaque colors only: the shadow is left out. */
function solid(c: string | undefined): string | undefined {
  if (!c || c === 'H') return undefined
  return PAL[c] ?? c
}
