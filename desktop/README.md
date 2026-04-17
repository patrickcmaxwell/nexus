# Desktop Voice Layer

Eve's home on your Mac. Handles listening, thinking, and speaking — all locally.

## Setup

```bash
cd desktop
pip install -r requirements.txt
python main.py
```

**Before running:** Make sure LM Studio is open with Qwen 3.5 loaded and the local server enabled (Developer tab → Local Server ON + CORS ON).

## Components

| Component | Tool | Purpose |
|-----------|------|---------|
| Speech-to-text | faster-whisper | Hears you (fully local) |
| Brain | LM Studio / Qwen 3.5 9B | Thinks (fully local) |
| Text-to-speech | Kokoro TTS | Speaks back (fully local) |
| Desktop control | PyAutoGUI | Opens apps, types, clicks |
| Cloud (optional) | Grok API | Only when you say "use grok" |

## Environment Variables

```bash
export GROK_API_KEY="your-key-here"   # Only needed for cloud mode
```

## Core Rules

- Fully offline by default
- Cloud only when you say: "use grok", "use internet", "go online", "ask cloud"
- Eve loads memory from `../memory/eve-private.md` on startup
