"""Reflex answers — the questions that should never cost an LLM round trip.

A brain call is 2-6s on a good day and 60s when both cloud lanes are congested.
"What time is it" does not need one. This is a small table of exact-answer
handlers checked before `fast_lane()` ever opens a socket.

Borrowed from sukeesh/jarvis, which is deliberately a non-AI assistant: most of
what people actually ask an assistant all day is a function call, not inference.

Design rules, in order of importance:

1. **Never guess.** A reflex only fires on a confident whole-phrase match. Anything
   ambiguous returns None and falls through to the normal brain chain. A wrong
   instant answer is far worse than a slow correct one.
2. **No side effects.** Every handler is a pure read. Nothing here can change
   state, so a misfire is at worst an irrelevant sentence.
3. **Speak like the persona.** These replies go straight to TTS without passing
   through the LLM, so they carry the butler register themselves.
"""
import datetime
import os
import re
import subprocess

# Phrases that must NOT be answered reflexively even if they contain a trigger:
# they are asking something the table cannot actually know.
_ESCAPE_HATCH = re.compile(
    r"\b(why|how come|explain|should|would|could|do you think|what if|"
    r"remind|schedule|set|change|tomorrow|yesterday|last week|next)\b", re.I)


def _say_time(_m=None):
    now = datetime.datetime.now()
    # 12-hour, no leading zero; "o'clock" when exactly on the hour reads better aloud
    hour = now.strftime("%I").lstrip("0") or "12"
    if now.minute == 0:
        return f"It's {hour} o'clock, sir."
    return f"It's {now.strftime('%I:%M %p').lstrip('0')}, sir."


def _say_date(_m=None):
    now = datetime.datetime.now()
    return f"It's {now.strftime('%A, %B')} {now.day}, sir."


def _say_battery(_m=None):
    try:
        out = subprocess.run(["pmset", "-g", "batt"], capture_output=True,
                             text=True, timeout=3).stdout
        pct = re.search(r"(\d+)%", out)
        if not pct:
            return None
        charging = "AC Power" in out or "charging" in out.lower()
        state = " and charging" if charging else ""
        return f"Battery is at {pct.group(1)} percent{state}, sir."
    except Exception:
        return None


def _say_memory(_m=None):
    """Reports true unified memory via `footprint`, not psutil RSS — the two
    disagreed by 3.5x when this project last measured them."""
    try:
        import psutil
        rss = psutil.Process().memory_info().rss / 1e6
    except Exception:
        return None
    fp = None
    try:
        out = subprocess.run(["footprint", str(os.getpid())],
                             capture_output=True, text=True, timeout=5).stdout
        m = re.search(r"phys_footprint:\s+(\d+)", out)
        if m:
            fp = int(m.group(1))
    except Exception:
        pass
    if fp:
        return f"I'm using {rss:.0f} megabytes of process memory, {fp} of unified, sir."
    return f"I'm using {rss:.0f} megabytes, sir."


def _say_uptime(_m=None):
    try:
        import psutil, time
        secs = time.time() - psutil.Process().create_time()
    except Exception:
        return None
    hours = secs / 3600
    if hours < 1:
        return f"I've been awake {secs / 60:.0f} minutes, sir."
    return f"I've been awake {hours:.1f} hours, sir."


def _say_day_progress(_m=None):
    now = datetime.datetime.now()
    end = now.replace(hour=23, minute=59, second=59)
    left = (end - now).total_seconds() / 3600
    return f"About {left:.0f} hours left in the day, sir."


def _flip_coin(_m=None):
    import random
    return f"{'Heads' if random.random() < 0.5 else 'Tails'}, sir."


def _roll_die(m):
    import random
    sides = int(m.group("sides") or 6)
    if not 2 <= sides <= 1000:
        return None
    return f"A {random.randint(1, sides)}, sir."


def _random_number(m):
    import random
    lo, hi = int(m.group("lo")), int(m.group("hi"))
    if lo >= hi:
        return None
    return f"{random.randint(lo, hi)}, sir."


def _password(_m=None):
    """Spoken-friendly but real: 4 words + 2 digits beats 'aX9$kQ' read aloud."""
    import random
    words = ("ember", "delta", "corvid", "maple", "quartz", "harbor", "sable",
             "vector", "onyx", "juniper", "cobalt", "fable", "meridian", "lyric")
    pw = "-".join(random.sample(words, 4)) + f"-{random.randint(10, 99)}"
    return f"Try {pw} — I'd note it down now, sir."


def _convert_temp(m):
    val = float(m.group("val"))
    unit = m.group("unit").lower()
    if unit.startswith(("f", "°f")):
        c = (val - 32) * 5 / 9
        return f"{val:g} Fahrenheit is {c:.1f} Celsius, sir."
    f = val * 9 / 5 + 32
    return f"{val:g} Celsius is {f:.1f} Fahrenheit, sir."


_LENGTH_TO_M = {"km": 1000.0, "kilometers": 1000.0, "kilometres": 1000.0,
                "mi": 1609.344, "miles": 1609.344, "mile": 1609.344,
                "m": 1.0, "meters": 1.0, "metres": 1.0,
                "ft": 0.3048, "feet": 0.3048, "foot": 0.3048,
                "in": 0.0254, "inches": 0.0254, "inch": 0.0254,
                "cm": 0.01, "centimeters": 0.01, "centimetres": 0.01}

_MASS_TO_KG = {"kg": 1.0, "kilograms": 1.0, "kilos": 1.0,
               "lb": 0.453592, "lbs": 0.453592, "pounds": 0.453592, "pound": 0.453592,
               "g": 0.001, "grams": 0.001,
               "oz": 0.0283495, "ounces": 0.0283495, "ounce": 0.0283495}


def _convert_units(m):
    val = float(m.group("val"))
    src, dst = m.group("src").lower(), m.group("dst").lower()
    for table in (_LENGTH_TO_M, _MASS_TO_KG):
        if src in table and dst in table:
            out = val * table[src] / table[dst]
            return f"{val:g} {src} is {out:.2f} {dst}, sir."
    return None                     # mixed dimensions ("miles to kilograms") fall to the brain


# Ordered most-specific first. Each entry: (compiled pattern, handler).
# Patterns are anchored to whole utterances rather than substrings so that
# "what time should I leave" cannot match the time reflex. Handlers taking a
# match object are called with it; zero-argument handlers ignore it.
_TABLE = [
    (re.compile(r"^(what'?s? |what is |tell me )?(the )?time( is it)?( now)?[?.]?$", re.I), _say_time),
    (re.compile(r"^what time is it([ ,]*(right )?now)?[?.]?$", re.I), _say_time),
    (re.compile(r"^(what'?s? |what is |tell me )?(the |today'?s )?date( today| is it)?[?.]?$", re.I), _say_date),
    (re.compile(r"^what day is it([ ,]*today)?[?.]?$", re.I), _say_date),
    (re.compile(r"^(what'?s? |how'?s? |check )?(the |my )?battery( level| percentage| status)?[?.]?$", re.I), _say_battery),
    (re.compile(r"^how much battery( do i have| is left)?[?.]?$", re.I), _say_battery),
    (re.compile(r"^(what'?s? |how much |check )?(your |the )?(ram|memory|footprint)( usage| are you using)?[?.]?$", re.I), _say_memory),
    (re.compile(r"^how much (ram|memory) are you using[?.]?$", re.I), _say_memory),
    (re.compile(r"^(what'?s? |how'?s? )?(your )?uptime[?.]?$", re.I), _say_uptime),
    (re.compile(r"^how long have you been (awake|running|up)[?.]?$", re.I), _say_uptime),
    (re.compile(r"^how much (of the )?day is left[?.]?$", re.I), _say_day_progress),
    # sukeesh-style deterministic tasks: generators and conversions
    (re.compile(r"^(flip|toss) a coin[?.]?$", re.I), _flip_coin),
    (re.compile(r"^(heads or tails)[?.]?$", re.I), _flip_coin),
    (re.compile(r"^roll a (die|dice)( with (?P<sides>\d+) sides)?[?.]?$", re.I), _roll_die),
    (re.compile(r"^roll a d(?P<sides>\d+)[?.]?$", re.I), _roll_die),
    (re.compile(r"^(give me |pick )?a random number (between|from) (?P<lo>-?\d+) (and|to) (?P<hi>-?\d+)[?.]?$", re.I), _random_number),
    (re.compile(r"^(generate|give me|make me)( a)?( new)? password[?.]?$", re.I), _password),
    (re.compile(r"^(what( is|'?s)? |convert )?(?P<val>-?\d+(\.\d+)?) (degrees )?(?P<unit>fahrenheit|celsius|°?[fc])( in| to| into)? (fahrenheit|celsius|°?[fc])[?.]?$", re.I), _convert_temp),
    (re.compile(r"^(what( is|'?s)? |convert )?(?P<val>-?\d+(\.\d+)?) (?P<src>[a-z]+)( in| to| into) (?P<dst>[a-z]+)[?.]?$", re.I), _convert_units),
]


def reflex(text):
    """Return an instant answer, or None to fall through to the brain chain."""
    if not text:
        return None
    cleaned = text.strip().strip('"“”')
    # Cheap length guard: every reflex phrase is short. A long utterance is a
    # real question even if it happens to contain "time". 10 accommodates the
    # longest legitimate phrase ("give me a random number between 1 and 100").
    if len(cleaned.split()) > 10:
        return None
    if _ESCAPE_HATCH.search(cleaned):
        return None
    for pattern, handler in _TABLE:
        m = pattern.match(cleaned)
        if m:
            try:
                return handler(m)
            except Exception:
                return None          # a broken reflex must never eat the turn
    return None


if __name__ == "__main__":
    hits = ["what time is it", "What's the time?", "time", "what day is it",
            "battery", "how much battery do I have", "uptime",
            "how much memory are you using", "what is the date",
            "flip a coin", "roll a dice", "roll a d20",
            "give me a random number between 1 and 100",
            "generate a password",
            "convert 100 fahrenheit to celsius", "what is 37 celsius in fahrenheit",
            "convert 5 miles to km", "10 kg to lbs"]
    misses = ["what time should I leave for the airport",
              "remind me at 5", "why is the battery draining so fast",
              "tell me about the time you helped me debug that", "what's the weather",
              "how do I check memory usage in python", "set a timer for 10 minutes",
              "roll a d1",                       # degenerate die
              "random number between 9 and 3",   # inverted range
              "convert 5 miles to kilograms"]    # mixed dimensions
    ok = True
    for t in hits:
        r = reflex(t)
        if not r:
            print(f"  MISS (should have fired): {t!r}")
            ok = False
    for t in misses:
        r = reflex(t)
        if r:
            print(f"  FALSE FIRE: {t!r} -> {r!r}")
            ok = False
    # exact-value checks, not just fired/not-fired
    assert "37.8" in (reflex("convert 100 fahrenheit to celsius") or ""), "temp conversion wrong"
    assert "8.05" in (reflex("convert 5 miles to km") or ""), "length conversion wrong"
    assert "22.05" in (reflex("10 kg to lbs") or ""), "mass conversion wrong"
    print("reflex table:", "PASS" if ok else "FAIL")
    print("sample:", reflex("what time is it"), "|", reflex("flip a coin"),
          "|", reflex("convert 5 miles to km"))
    raise SystemExit(0 if ok else 1)
