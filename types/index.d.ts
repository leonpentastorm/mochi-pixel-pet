/** Something waiting on the person: a question Claude asked, or a tool call to approve. */
export type PetAlert = {
  /** The tool_use_id of the call that is waiting ('' when the engine gave none). */
  id: string
  tool: string
  kind: 'question' | 'permission'
}

export type PetState = {
  /** A main-thread turn is running. */
  busy: boolean
  /** Tool calls in flight (any loop). */
  tools: number
  alerts: PetAlert[]
  /** Epoch ms until which the pet celebrates; 0 when not. */
  happyUntil: number
  /** Epoch ms of the last activity, for falling asleep. */
  lastActive: number
  asleep: boolean
}

declare module 'claude-code' {
  interface PluginState {
    'pixel-pet': {
      pet: Shaped<PetState>
      /** Animation frame counter, ticked only while a terminal draws the pane. */
      tick: number
    }
  }
}
