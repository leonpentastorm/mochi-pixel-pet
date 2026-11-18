import { expect, test } from 'claude-code/testing'

import { desktopFramesJson } from '../hooks/art'

test('desktop frames export', () => {
  const json = desktopFramesJson()
  const art = JSON.parse(json) as { width: number; height: number; moods: Record<string, { rows: string[] }[]> }
  for (const frames of Object.values(art.moods)) {
    for (const f of frames) {
      expect(f.rows.length).toBe(art.height)
      for (const row of f.rows) expect(row.length).toBe(art.width)
    }
  }
})
