# ✦ Vibe

A modern, mouse-aware terminal text editor for macOS with an AI copilot built right into the workspace. It is delivered as a single `.sh` file, but feels closer to a tiny desktop app: full-screen chrome, clickable panes, live window resizing, file navigation, editing, and an assistant beside your code.

## Launch

```sh
chmod +x vibe.sh
./vibe.sh
```

Open a specific file:

```sh
./vibe.sh path/to/file.js
```

Vibe uses macOS Terminal, iTerm2, Warp, or another ANSI-compatible terminal. Drag the window edges to resize it; the layout redraws automatically. Click a pane or press `Tab` to move between the explorer, editor, and AI input.

## Controls

| Action | Shortcut |
| --- | --- |
| Save | `Ctrl-S` |
| Open a file | `Ctrl-P` |
| Create a file | `Ctrl-N` |
| Focus file explorer | `Ctrl-B` |
| Focus AI input | `Ctrl-K` |
| Quit | `Ctrl-Q` |
| Move between panes | `Tab` or click |
| Select/open files | Arrow keys and `Enter` |
| Send AI question | Type beneath the chatbot and press `Enter` |

## AI setup

Vibe reads `OPENAI_API_KEY` from the environment or from a private `.env.local` file next to `vibe.sh`. The key is deliberately not embedded in the script, where it could be extracted or accidentally committed.

The default model is `gpt-5.6`. Override it when launching if needed:

```sh
OPENAI_MODEL=gpt-5.6-terra ./vibe.sh
```

API usage is billed through the OpenAI Platform project associated with your key.

## Requirements

- macOS
- `zsh`, `curl`, and `osascript` (included with macOS)
- An ANSI terminal with 256-color support
- Recommended minimum window size: 72 × 16

## Security

`.env.local` is ignored by Git. Never paste API keys into `vibe.sh`, screenshots, issues, or commits. If a key is ever exposed, revoke it in the OpenAI Platform dashboard and create a replacement.
