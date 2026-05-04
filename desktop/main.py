"""
Nexus Desktop — Eve Intelligence Layer
FastAPI WebSocket server: STT (Whisper) + LM Studio inference.
TTS handled by frontend via ElevenLabs (nexus-web /api/eve/tts).

Run: python main.py
Requires: pip install -r requirements.txt
"""

import asyncio
import threading
import queue
import json
import os
import uuid
from datetime import datetime
from pathlib import Path

import sounddevice as sd
import numpy as np
import soundfile as sf
import requests
from faster_whisper import WhisperModel
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

# ── Config ────────────────────────────────────────────────────────────────────
LM_STUDIO_URL = "http://localhost:1234/v1/chat/completions"
LM_MODEL      = "qwen3.5"
MEMORY_PATH   = Path(__file__).parent.parent / "memory"
DATA_DIR      = Path.home() / ".nexus" / "desktop"
MSGS_DIR      = DATA_DIR / "messages"
CONVOS_FILE   = DATA_DIR / "conversations.json"
DATA_DIR.mkdir(parents=True, exist_ok=True)
MSGS_DIR.mkdir(exist_ok=True)

# ── Models ────────────────────────────────────────────────────────────────────
print("Loading Whisper (STT)...", flush=True)
whisper_model = WhisperModel("base", device="cpu")
print("Whisper ready.", flush=True)

# ── Eve context ───────────────────────────────────────────────────────────────
def load_context() -> str:
    parts = []
    for name in ["eve-base", "eve-private"]:
        p = MEMORY_PATH / f"{name}.md"
        if p.exists():
            parts.append(p.read_text(encoding="utf-8"))
    return "\n\n".join(parts) if parts else (
        "You are Eve. You are the private AI command intelligence of Patrick Maxwell, "
        "operating inside the Nexus command platform. Address Patrick as 'sir' or 'Director'. "
        "Be direct, sharp, efficient. Dry wit is permitted. Keep responses concise — "
        "you are speaking aloud, not writing a report. Short sentences, natural speech rhythm."
    )

EVE_CONTEXT           = load_context()
conversation_history: list[dict]  = []
current_conv_id: str | None       = None

# ── Conversation persistence (local JSON) ─────────────────────────────────────
def load_conversations() -> list:
    if CONVOS_FILE.exists():
        try: return json.loads(CONVOS_FILE.read_text())
        except: pass
    return []

def save_conversations(convos: list):
    CONVOS_FILE.write_text(json.dumps(convos, indent=2))

def save_message_local(conv_id: str, role: str, text: str):
    f = MSGS_DIR / f"{conv_id}.json"
    msgs = []
    if f.exists():
        try: msgs = json.loads(f.read_text())
        except: pass
    msgs.append({"role": role, "content": text, "ts": datetime.utcnow().isoformat()})
    f.write_text(json.dumps(msgs, indent=2))

def ensure_conversation(first_text: str) -> str:
    global current_conv_id
    if current_conv_id:
        return current_conv_id
    conv_id = str(uuid.uuid4())
    current_conv_id = conv_id
    convos = load_conversations()
    convos.insert(0, {"id": conv_id, "title": first_text[:60], "created_at": datetime.utcnow().isoformat()})
    save_conversations(convos)
    return conv_id

# ── Shared async state ────────────────────────────────────────────────────────
event_queue: asyncio.Queue      = asyncio.Queue()
command_queue: queue.Queue      = queue.Queue()
main_loop: asyncio.AbstractEventLoop | None = None
active_ws: WebSocket | None     = None

def emit(event: dict):
    if main_loop:
        main_loop.call_soon_threadsafe(event_queue.put_nowait, json.dumps(event))

def set_state(status: str):
    emit({"type": "state", "status": status})

# ── LM Studio ─────────────────────────────────────────────────────────────────
def ask_local(text: str) -> str:
    msgs = [{"role": "system", "content": EVE_CONTEXT}]
    msgs.extend(conversation_history[-12:])
    msgs.append({"role": "user", "content": text})
    try:
        r = requests.post(LM_STUDIO_URL, json={
            "model": LM_MODEL, "messages": msgs,
            "temperature": 0.7, "max_tokens": 500,
        }, timeout=45)
        return r.json()["choices"][0]["message"]["content"]
    except Exception as e:
        return "I can't reach my local brain right now. Is LM Studio running?"

# ── Process a turn ────────────────────────────────────────────────────────────
def process_message(text: str):
    set_state("thinking")
    response = ask_local(text)
    conversation_history.append({"role": "user",      "content": text})
    conversation_history.append({"role": "assistant",  "content": response})
    conv_id = ensure_conversation(text)
    save_message_local(conv_id, "user",      text)
    save_message_local(conv_id, "assistant", response)
    # Frontend handles TTS + nexus-web persistence
    emit({"type": "response", "text": response, "conversation_id": conv_id})
    set_state("idle")

# ── Voice thread (blocking STT on background thread) ──────────────────────────
def voice_loop():
    print("Voice loop ready.", flush=True)
    while True:
        try:
            cmd = command_queue.get(timeout=0.5)
        except queue.Empty:
            continue

        action = cmd.get("cmd")

        if action == "listen":
            set_state("listening")
            try:
                audio = sd.rec(int(5 * 16000), samplerate=16000, channels=1, dtype="float32")
                sd.wait()
                set_state("thinking")
                segments, _ = whisper_model.transcribe(audio.flatten(), beam_size=5)
                text = " ".join(s.text for s in segments).strip()
                if text:
                    emit({"type": "transcript", "text": text, "final": True})
                    process_message(text)
                else:
                    set_state("idle")
            except Exception as e:
                print(f"Voice error: {e}", flush=True)
                set_state("idle")

        elif action == "send":
            text = cmd.get("text", "").strip()
            if text:
                emit({"type": "transcript", "text": text, "final": True})
                process_message(text)

        elif action == "new":
            global current_conv_id
            current_conv_id = None
            conversation_history.clear()
            emit({"type": "cleared"})

# ── FastAPI ───────────────────────────────────────────────────────────────────
app = FastAPI()
app.add_middleware(CORSMiddleware,
    allow_origins=["http://localhost:5173"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/api/conversations")
async def list_conversations():
    return load_conversations()

@app.get("/api/conversations/{conv_id}/messages")
async def get_messages(conv_id: str):
    f = MSGS_DIR / f"{conv_id}.json"
    return json.loads(f.read_text()) if f.exists() else []

@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    global active_ws
    await ws.accept()
    active_ws = ws
    await ws.send_text(json.dumps({"type": "ready", "conversation_id": current_conv_id}))
    relay = asyncio.create_task(_relay(ws))
    try:
        while True:
            data = await ws.receive_text()
            command_queue.put(json.loads(data))
    except WebSocketDisconnect:
        pass
    finally:
        relay.cancel()
        active_ws = None

async def _relay(ws: WebSocket):
    while True:
        msg = await event_queue.get()
        try:
            await ws.send_text(msg)
        except:
            break

@app.on_event("startup")
async def startup():
    global main_loop
    main_loop = asyncio.get_event_loop()
    threading.Thread(target=voice_loop, daemon=True).start()
    print("✅ Eve is ready at ws://localhost:8765/ws", flush=True)

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8765, log_level="warning")
