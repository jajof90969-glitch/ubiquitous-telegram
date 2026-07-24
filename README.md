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

Vibe uses the Gemini API free tier. Create a key in [Google AI Studio](https://aistudio.google.com/apikey), then save it in a private `.env.local` file next to `vibe.sh`:

```sh
GEMINI_API_KEY=your_key_here
```

The default model is `gemini-2.5-flash`, a stable model with free-tier input and output usage. Override it when launching if needed:

```sh
GEMINI_MODEL=gemini-2.5-flash-lite ./vibe.sh
```

Free-tier rate limits apply and vary by account and region. Google states that free-tier content may be used to improve its products. You do not need to enable billing to use an eligible free-tier project.

## Requirements

- macOS
- `zsh`, `curl`, and `osascript` (included with macOS)
- An ANSI terminal with 256-color support
- Recommended minimum window size: 72 × 16

## Security

`.env.local` is ignored by Git. Never paste API keys into `vibe.sh`, screenshots, issues, or commits. If a key is ever exposed, revoke it in Google AI Studio and create a replacement.
