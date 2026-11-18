# Mochi, a pixel-art pet for Claude Code

Mochi is a little animated pixel-art cat that lives in a panel beside your Claude Code chat and reacts to what Claude is doing:

- **Idle**: breathes gently and blinks now and then.
- **Working**: taps away on a tiny laptop while Claude works on a reply.
- **Sleeping**: dozes off, Z's floating up, after 90 seconds with nothing going on.
- **Happy**: jumps with its arms up and sparkles when a reply finishes.
- **Alert**: bounces and waves under a "Claude has a question!" speech bubble whenever Claude asks you something or needs your approval, and sends one desktop notification (taken back once you've answered).

The button under Mochi pets it, or during an alert, takes you to the question: in the terminal it scrolls the chat there; in the desktop app, which doesn't let mods scroll the chat, it points you to the question at the bottom of the chat.

Type `/pet` to bring the panel back if you close it.

## Mochi on your desktop (Windows)

Mochi also lives on your Windows desktop, outside the Claude window, in a see-through window that stays on top. It starts by itself when a Claude Code session starts; each session reports how it is doing, and the desktop Mochi shows the busiest of them:

- **One line above Mochi's head per chat that needs you**: "website: has a question!", "api-server: done ✓". Click a line to open that chat in the Claude app.
- **Click Mochi** to open the chat that needs you most (or the one you used last) and hush the sound.
- **Drag Mochi** anywhere; **resize** it with the corner grip or the mouse wheel.
- **A sound loops** while a question waits or a finished chat is unseen. Right-click Mochi to turn the sound off, choose your own sound file (WAV, MP3, WMA, M4A), or go back to the built-in chime.
- Right-click also has size presets, **Start with Windows**, **Start when Claude starts**, and **Quit Mochi**.

It needs nothing installed: it is a Windows PowerShell script (`desktop/mochi-desktop.ps1`). Sessions write their state to `%USERPROFILE%\.claude\mochi\sessions\`; Mochi's settings are in `%USERPROFILE%\.claude\mochi\desktop.json`.

## Install

At the prompt of a Claude Code terminal session:

```
/plugin install pixel-pet --marketplace YOUR-USERNAME/mochi-pixel-pet
```

Answer `y` to add the marketplace, then press Enter to pick the user scope.

From a shell:

```
claude plugin install pixel-pet --marketplace YOUR-USERNAME/mochi-pixel-pet
```

In the desktop app, where `/plugin` does not run: click **+** next to the prompt box, then **Plugins**, **Add marketplace** with `YOUR-USERNAME/mochi-pixel-pet`, then **Add plugin**.
