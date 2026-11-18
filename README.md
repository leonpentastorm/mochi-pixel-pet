<p align="center"><img src="assets/mochi-icon.png" width="128" alt="Mochi, a pixel-art cat"></p>

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
- **Click Mochi** to open the chat that needs you most (or the one you used last) and hush the sound. Going to the Claude window yourself hushes it too: the waving and the sound stop as soon as Claude is in front, while the line stays until you answer or open that chat. And if you are already in Claude and active (mouse or keyboard in the last 2 minutes) when a question or reply comes in, Mochi doesn't ring at all, just shows the line.
- **Tray icon**: Mochi has no taskbar button and stays out of Alt+Tab; its face in the system tray hides or shows it (left-click) and has Open Claude and Quit (right-click).
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

### The easy way: ask Claude

Paste this into any Claude Code chat (terminal, desktop app or IDE):

> Install the Mochi pixel pet for me: run `claude plugin marketplace add leonpentastorm/mochi-pixel-pet` and then `claude plugin install pixel-pet@mochi-pixel-pet --scope user`.

Claude runs the two commands; Mochi shows up in every Claude Code chat you start after that (and, on Windows, on your desktop).

### Or do it yourself

At the prompt of a Claude Code terminal session:

```
/plugin install pixel-pet --marketplace leonpentastorm/mochi-pixel-pet
```

Answer `y` to add the marketplace, then press Enter to pick the user scope.

From a shell:

```
claude plugin marketplace add leonpentastorm/mochi-pixel-pet
claude plugin install pixel-pet@mochi-pixel-pet --scope user
```

In the Claude desktop app: click **+** next to the prompt box, then **Plugins**, **Add marketplace** with `leonpentastorm/mochi-pixel-pet`, then **Add plugin** and pick **pixel-pet**.

Start a new chat afterwards: Mochi loads when a session starts.

### Updating and removing

```
claude plugin marketplace update mochi-pixel-pet
claude plugin update pixel-pet@mochi-pixel-pet
```

```
claude plugin uninstall pixel-pet@mochi-pixel-pet
claude plugin marketplace remove mochi-pixel-pet
```

To stop the desktop Mochi from starting with Claude without uninstalling, right-click it and untick **Start when Claude starts**.

### For Claude: installing this plugin

If a person asks you to install Mochi from this repository, run, in order:

1. `claude plugin marketplace add leonpentastorm/mochi-pixel-pet` (adds this repository as a plugin marketplace named `mochi-pixel-pet`)
2. `claude plugin install pixel-pet@mochi-pixel-pet --scope user` (installs the `pixel-pet` plugin for all their sessions)
3. `claude plugin list` and check that `pixel-pet@mochi-pixel-pet` shows **enabled**.

Then tell them to start a new chat to see Mochi. If `claude` is not on the PATH (a desktop-app-only setup), give them the desktop-app steps above instead. Mochi needs a Claude Code version with plugin hooks modules (function hooks); the desktop pet part needs Windows and Windows PowerShell 5.1, both standard on Windows 10 and 11.

## License

MIT: use, change and share Mochi freely; keep the copyright notice in [LICENSE](LICENSE).
