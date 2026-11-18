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
- **Drag Mochi** anywhere (it hangs on to the cursor with both paws while you carry it); **resize** it with the corner grip or the mouse wheel.
- **Show chats in progress** (on by default): a fainter line for every chat Claude is working on. When nothing runs, or with it off, Mochi shows just itself.
- **Names**: a line names the chat's project folder. Chats with no real folder are "Project 1", "Project 2"...; chats sharing a folder are told apart as "#1", "#2".
- **Wander around** (on by default): now and then, while idle, Mochi walks off left or right until it slams into the edge of the screen, falls over seeing stars, gets up, licks its paw, then either walks back the other way or stands about for a while.
- **DVD bounce mode**: Mochi flies about the screen, bouncing off every edge and changing fur color at each bounce. Put the cursor on it and it stops and holds on to the cursor; move away and it flies on. It parks while a chat needs you, and takes off again after.
- **Zoomies**: after napping for 3 minutes (`napMinutes` in the settings), Mochi takes off DVD style until you catch it with the cursor; then it lands and stays up a minute.
- **Always on top** (on by default): turn it off to let other windows cover Mochi.
- **A sound loops** while a question waits or a finished chat is unseen. Right-click → **Sound** to turn it off or pick it: a ringtone of your own saved as `%USERPROFILE%\.claude\mochi\phone.mp3` (the default when it is there), the built-in chime, or any sound file (WAV, MP3, WMA, M4A).
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
