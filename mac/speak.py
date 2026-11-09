# /// script
# requires-python = ">=3.10"
# dependencies = ["truststore"]
# ///
"""Terminal Jarvis voice (macOS).

  (no args)      Codex "Stop" hook: reads the finished turn (JSON) on stdin and speaks the reply's opening
                 paragraph in the background, so Codex never waits on audio.
  --say TEXT     speak TEXT in the background (the greeting)
  --check        do nothing (the installer runs this once to prepare the environment)
Voice: Fish Audio with your key from the Keychain (state voice = fish), else the macOS voice (Daniel).
"""
import json
import os
import re
import signal
import subprocess
import sys
import time
import uuid

TJ = os.path.expanduser("~/.terminal-jarvis")


def state():
    try:
        with open(os.path.join(TJ, "state.json"), encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def log(m):
    try:
        with open(os.path.join(TJ, "voice.log"), "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + m + "\n")
    except Exception:
        pass


def opening(msg):
    """First prose paragraph (skip code, tables, headings), markdown stripped, <= ~420 chars."""
    text = ""
    for p in re.split(r"\r?\n\s*\r?\n", msg.strip()):
        t = p.strip()
        if not t or t.startswith("```") or t.startswith("|") or t.startswith("#"):
            continue
        text = t
        break
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"`([^`]+)`", r"\1", text)
    text = re.sub(r"\s+", " ", re.sub(r"[*_#>]", "", text)).strip()
    if len(text) > 420:
        cut = text[:420]
        end = max(cut.rfind(". "), cut.rfind("? "), cut.rfind("! "))
        text = cut[: end + 1] if end > 120 else cut
    return text


def spawn(text):
    """Speak in a detached worker; a new reply cuts off the previous one."""
    if not text:
        return
    pid_file = os.path.join(TJ, "speaking.pid")
    try:
        old = int(open(pid_file).read().strip())
        os.killpg(old, signal.SIGTERM)   # the worker and its afplay/say
    except Exception:
        pass
    path = os.path.join(TJ, "say-%s.txt" % uuid.uuid4().hex[:8])
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    p = subprocess.Popen([sys.executable, os.path.abspath(__file__), "--worker", path], start_new_session=True,
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with open(pid_file, "w") as f:
        f.write(str(p.pid))


def speak_mac(text, voice):
    if subprocess.run(["say", "-v", voice, text], stderr=subprocess.DEVNULL).returncode != 0:
        subprocess.run(["say", text])


def worker(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    try:
        os.remove(path)
    except OSError:
        pass
    s = state()
    if s.get("voice") == "fish":
        try:
            import truststore
            import urllib.request

            truststore.inject_into_ssl()
            key = subprocess.run(["security", "find-generic-password", "-s", s.get("fish_key_slot", "terminal-jarvis-fish"), "-w"],
                                 capture_output=True, text=True).stdout.strip()
            if not key:
                raise RuntimeError("no Fish key in the Keychain")
            body = json.dumps({"text": text, "reference_id": s.get("fish_voice_id"), "format": "mp3"}).encode("utf-8")
            req = urllib.request.Request("https://api.fish.audio/v1/tts", data=body, method="POST", headers={
                "Authorization": "Bearer " + key, "model": s.get("fish_model", "s1"),
                "Content-Type": "application/json; charset=utf-8"})
            t0 = time.time()
            with urllib.request.urlopen(req, timeout=30) as r:
                audio = r.read()
            out = os.path.join(TJ, "reply.mp3")
            with open(out, "wb") as f:
                f.write(audio)
            log("fish ok %.1fs, %d chars" % (time.time() - t0, len(text)))
            subprocess.run(["afplay", out])
            return
        except Exception as e:  # noqa: BLE001
            log("fish failed, using the macOS voice: %s" % e)
    speak_mac(text, s.get("mac_voice", "Daniel"))


def main():
    args = sys.argv[1:]
    if args[:1] == ["--check"]:
        return
    if args[:1] == ["--worker"] and len(args) > 1:
        worker(args[1])
        return
    s = state()
    if not s.get("voice") or s.get("voice") == "none" or s.get("voice_muted"):
        return
    if args[:1] == ["--say"] and len(args) > 1:
        spawn(" ".join(args[1:]))
        return
    try:
        j = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        return
    if j.get("stop_hook_active"):
        return
    spawn(opening(str(j.get("last_assistant_message") or "")))


if __name__ == "__main__":
    main()
