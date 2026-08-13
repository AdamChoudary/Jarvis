#!/usr/bin/env python3
"""Jarvis Local Brain — MLX-powered local LLM, offline last resort.

This docstring used to claim local was the *primary* brain with NIM/Zen as
fallbacks — backwards from reality, corrected 2026-07-30. The real priority
order (see jarvis_ear.py's fast_lane()) is NIM -> Zen (cloud) -> this module
LAST: local generation currently measures single-digit tok/s, far below the
"35 tok/s" once assumed, and this deliberately never loads first — doing so
would invert both the real latency ordering and the daemon's RAM budget.
Uses mlx-lm for Apple Silicon native inference (currently `qwen-3b`, see
MODELS below).

Features:
  - Streaming generation with first-token tracking
  - Conversation-aware with system prompt injection
  - Automatic model download on first use
  - Health monitoring and fallback chain

Usage:
    from jarvis_voice.jarvis_brain import JarvisBrain
    brain = JarvisBrain()
    response = brain.think("What's on my schedule today?")
"""
import json, os, sys, time, threading
from pathlib import Path

HOME = os.path.expanduser("~")
MODELS_DIR = os.path.join(HOME, ".hermes", "models")
LOG_PATH = os.path.join(HOME, ".hermes", "jarvis-voice", "brain.log")

# Model configurations
MODELS = {
    "qwen-4b": {
        "repo": "mlx-community/Qwen3-4B-Instruct-2507-4bit",
        "size_gb": 2.5,
        "description": "Qwen3 4B — fast local, 25 tok/s on M1",
    },
    "qwen-3b": {
        "repo": "mlx-community/Qwen2.5-3B-Instruct-4bit",
        "size_gb": 1.8,
        "description": "Qwen2.5 3B — lighter, 35 tok/s on M1",
    },
}

def log(msg):
    line = f"[brain {time.strftime('%H:%M:%S')}] {msg}"
    print(line, file=sys.stderr)
    try:
        with open(LOG_PATH, "a") as f:
            f.write(line + "\n")
    except:
        pass

class JarvisBrain:
    def __init__(self, model_key: str = "qwen-3b"):
        self.model_key = model_key
        self.model_config = MODELS.get(model_key, MODELS["qwen-3b"])
        self._model = None
        self._tokenizer = None
        self._lock = threading.Lock()
        self._loaded = False
        self._load_time = 0

    def _ensure_model(self):
        """Download model if not cached, then load.

        Double-checked locking, mirroring jarvis_memory_v7.py's _get_model():
        without it, two concurrent callers (a foreground turn and an already-
        in-flight background load from a prior abandoned turn — see
        jarvis_ear.py's _local_brain) would each see _loaded is False and
        both call mlx_lm.load() at once, doubling RAM at the exact moment
        this fallback exists to protect it, and risking self._model/
        self._tokenizer being read mid-reassignment by the other thread (a
        torn model/tokenizer pair, not just wasted work)."""
        if self._loaded:
            return
        with self._lock:
            if self._loaded:
                return
            from mlx_lm import load, generate

            repo = self.model_config["repo"]
            model_path = os.path.join(MODELS_DIR, repo.replace("/", "_"))

            t0 = time.time()
            log(f"Loading {self.model_config['description']}...")

            try:
                self._model, self._tokenizer = load(repo)
                self._loaded = True
                self._load_time = time.time() - t0
                log(f"Model loaded in {self._load_time:.1f}s")
            except Exception as e:
                log(f"Model load failed: {e}")
                raise

    def _build_prompt(self, prompt: str, system: str = "") -> str:
        """Format messages into model prompt string via chat template."""
        messages = []
        if system:
            messages.append({"role": "system", "content": system})
        messages.append({"role": "user", "content": prompt})
        if hasattr(self._tokenizer, "apply_chat_template"):
            return self._tokenizer.apply_chat_template(
                messages, tokenize=False, add_generation_prompt=True
            )
        return prompt

    def think(self, prompt: str, system: str = "", max_tokens: int = 500,
              temperature: float = 0.7) -> str:
        """Generate a response to a prompt. Returns full text."""
        self._ensure_model()

        from mlx_lm import generate
        from mlx_lm.sample_utils import make_sampler

        prompt_str = self._build_prompt(prompt, system)
        sampler = make_sampler(temp=temperature)

        with self._lock:
            t0 = time.time()
            response = generate(
                self._model,
                self._tokenizer,
                prompt=prompt_str,
                max_tokens=max_tokens,
                sampler=sampler,
            )
            elapsed = time.time() - t0

        tokens = len(response.split())
        tok_per_sec = tokens / elapsed if elapsed > 0 else 0
        log(f"Generated {tokens} tokens in {elapsed:.1f}s ({tok_per_sec:.0f} tok/s)")

        return response

    def think_stream(self, prompt: str, system: str = "", max_tokens: int = 500,
                     temperature: float = 0.7):
        """Generator that yields tokens as they're generated."""
        self._ensure_model()

        from mlx_lm import stream_generate
        from mlx_lm.sample_utils import make_sampler

        prompt_str = self._build_prompt(prompt, system)
        sampler = make_sampler(temp=temperature)

        with self._lock:
            for token in stream_generate(
                self._model,
                self._tokenizer,
                prompt=prompt_str,
                max_tokens=max_tokens,
                sampler=sampler,
            ):
                yield token

    def is_available(self) -> bool:
        """Check if the model is loaded and ready."""
        return self._loaded

    def unload(self):
        """Unload model to free memory."""
        self._model = None
        self._tokenizer = None
        self._loaded = False
        log("Model unloaded")

    def stats(self) -> dict:
        return {
            "model": self.model_config["description"],
            "loaded": self._loaded,
            "load_time": round(self._load_time, 1) if self._load_time else None,
            "size_gb": self.model_config["size_gb"],
        }


# ── Lazy singleton ────────────────────────────────────────────────────────────
_brain = None

def get_brain(model_key: str = "qwen-3b") -> JarvisBrain:
    global _brain
    if _brain is None:
        _brain = JarvisBrain(model_key)
    return _brain


# ── CLI ───────────────────────────────────────────────────────────────────────
def main():
    if len(sys.argv) < 2:
        print("Usage: python jarvis_brain.py [stats|think <prompt>|download]")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "stats":
        brain = get_brain()
        print(json.dumps(brain.stats(), indent=2))
    elif cmd == "think":
        prompt = " ".join(sys.argv[2:])
        brain = get_brain()
        response = brain.think(prompt)
        print(response)
    elif cmd == "download":
        brain = get_brain()
        brain._ensure_model()
        print("Model downloaded and loaded")
    else:
        print(f"Unknown command: {cmd}")

if __name__ == "__main__":
    main()
