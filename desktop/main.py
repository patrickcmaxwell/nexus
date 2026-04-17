"""
Nexus Desktop Voice Layer
Eve — local voice assistant running on your Mac

Requirements:
    pip install faster-whisper sounddevice numpy pyaudio kokoro soundfile pyautogui requests

Make sure LM Studio is running with the local server enabled before starting.
Run: python main.py
"""

import sounddevice as sd
import numpy as np
import requests
import os
from faster_whisper import WhisperModel
from kokoro import KPipeline
import soundfile as sf
import time

print("🌙 Nexus (Eve) starting — fully offline by default")

# ── Config ──────────────────────────────────────────────────────────────────
LM_STUDIO_URL = "http://localhost:1234/v1/chat/completions"
LM_MODEL = "qwen3.5"           # Match the model name shown in LM Studio
GROK_API_KEY = os.getenv("GROK_API_KEY", "")
MEMORY_PATH = os.path.join(os.path.dirname(__file__), "../memory")

# Phrases that allow cloud access (everything else stays local)
CLOUD_PHRASES = ["use grok", "use internet", "go online", "search the web", "ask cloud"]

# ── Load models ──────────────────────────────────────────────────────────────
print("Loading Whisper (speech-to-text)...")
whisper = WhisperModel("base", device="cpu")

print("Loading Kokoro (text-to-speech)...")
pipeline = KPipeline(lang_code='a')  # 'a' = American English

# ── Load Eve's memory ────────────────────────────────────────────────────────
def load_eve_context(user_id="patrick"):
    """Load the appropriate memory files based on who is using the system."""
    base = open(f"{MEMORY_PATH}/eve-base.md").read()
    if user_id == "patrick":
        private = open(f"{MEMORY_PATH}/eve-private.md").read()
        return f"{base}\n\n{private}"
    else:
        shared = open(f"{MEMORY_PATH}/eve-shared.md").read()
        return f"{base}\n\n{shared}"

EVE_CONTEXT = load_eve_context("patrick")

# ── Voice functions ──────────────────────────────────────────────────────────
def listen(duration_seconds=5):
    """Record audio from microphone."""
    print("🎤 Listening...")
    audio = sd.rec(
        int(duration_seconds * 16000),
        samplerate=16000,
        channels=1,
        dtype='float32'
    )
    sd.wait()
    return audio.flatten()

def transcribe(audio):
    """Convert audio to text using Whisper (fully local)."""
    segments, _ = whisper.transcribe(audio, beam_size=5)
    return " ".join(seg.text for seg in segments).strip()

def speak(text):
    """Convert text to speech using Kokoro (fully local)."""
    print(f"🌙 Eve: {text}")
    try:
        audio = pipeline(text, voice='af_heart')
        sf.write("response.wav", audio, 24000)
        os.system("afplay response.wav")  # macOS audio playback
    except Exception as e:
        print(f"⚠️  Speech error: {e}")

# ── Brain functions ───────────────────────────────────────────────────────────
def ask_local(user_message):
    """Send message to LM Studio (fully offline)."""
    try:
        response = requests.post(LM_STUDIO_URL, json={
            "model": LM_MODEL,
            "messages": [
                {"role": "system", "content": EVE_CONTEXT},
                {"role": "user", "content": user_message}
            ],
            "temperature": 0.7,
            "max_tokens": 500
        }, timeout=30)
        return response.json()["choices"][0]["message"]["content"]
    except Exception as e:
        return f"Sorry, I couldn't reach my local brain. Is LM Studio running? ({e})"

def call_grok(user_message):
    """Call Grok API — only used when explicitly allowed."""
    if not GROK_API_KEY:
        return "Grok API key not set. Add GROK_API_KEY to your environment."
    try:
        from openai import OpenAI
        client = OpenAI(base_url="https://api.x.ai/v1", api_key=GROK_API_KEY)
        response = client.chat.completions.create(
            model="grok-3",
            messages=[
                {"role": "system", "content": EVE_CONTEXT},
                {"role": "user", "content": user_message}
            ],
            temperature=0.7,
            max_tokens=800
        )
        return response.choices[0].message.content
    except Exception as e:
        return f"Sorry, I couldn't reach Grok right now. ({e})"

def call_arena(endpoint, payload):
    """Tell Arena to execute an action."""
    try:
        r = requests.post(f"http://localhost:3001{endpoint}", json=payload, timeout=10)
        return r.json()
    except Exception as e:
        return {"error": str(e)}

# ── Main loop ─────────────────────────────────────────────────────────────────
print("✅ Eve is ready. Start talking.\n")
speak("I'm here. What do you need?")

while True:
    try:
        audio = listen()
        text = transcribe(audio)

        if not text:
            continue

        print(f"👤 You: {text}")
        text_lower = text.lower()

        # Check if user is allowing cloud access
        if any(phrase in text_lower for phrase in CLOUD_PHRASES):
            speak("Switching to Grok. One moment.")
            response = call_grok(text)

        # Check for sync command
        elif "hey sync" in text_lower or "sync with home" in text_lower:
            speak("Syncing with home. One moment.")
            # TODO: trigger Supabase sync
            response = "Sync complete."

        # Everything else stays local
        else:
            response = ask_local(text)

        speak(response)

    except KeyboardInterrupt:
        print("\n👋 Eve shutting down.")
        break
    except Exception as e:
        print(f"⚠️  Error: {e}")
        time.sleep(1)
