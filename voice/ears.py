# /// script
# requires-python = ">=3.10,<3.13"
# dependencies = [
#   "faster-whisper>=1.0",
#   "sounddevice>=0.4.6",
#   "numpy",
#   "truststore",
#   "pynput>=1.7.6; sys_platform == 'darwin'",
#   "pyobjc-framework-Cocoa; sys_platform == 'darwin'",
#   "pyobjc-framework-ApplicationServices; sys_platform == 'darwin'",
# ]
# ///
"""Terminal Jarvis ears: push-to-talk speech-to-text that runs on your own computer (faster-whisper).

Nothing is uploaded: audio is recorded only while the talk key is held and transcribed locally.

Modes
  --warmup   download the speech model once (the installer runs this), then exit
  --serve    Windows: the Jarvis HUD drives it over stdin/stdout
               in:  "start" | "stop" | "quit"
               out: "READY" | "LISTENING" | "TEXT <base64 utf-8>" | "ERROR <message>"
  --mac      macOS: listens for the talk key itself (only while a terminal app is in front),
             then types the words into the terminal and presses Return.
"""
import argparse
import base64
import json
import os
import sys
import threading
import time

try:  # use the system's certificates (antivirus HTTPS scanning, company proxies)
    import truststore

    truststore.inject_into_ssl()
except Exception:
    pass

os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")
os.environ.setdefault("HF_HUB_VERBOSITY", "error")       # no "unauthenticated requests" nag
os.environ.setdefault("HF_HUB_DISABLE_PROGRESS_BARS", "1")

RATE = 16000


def load_state(path):
    try:
        with open(path, encoding="utf-8-sig") as f:
            return json.load(f)
    except Exception:
        return {}


class Ears:
    def __init__(self, model_name, models_dir):
        self.model_name = model_name or "base.en"
        self.models_dir = models_dir
        self.model = None
        self.loaded = threading.Event()
        self.load_error = None
        self.chunks = []
        self.stream = None
        self.lock = threading.Lock()

    def load(self):
        try:
            from faster_whisper import WhisperModel

            os.makedirs(self.models_dir, exist_ok=True)
            self.model = WhisperModel(self.model_name, device="cpu", compute_type="int8",
                                      download_root=self.models_dir)
        except Exception as e:  # noqa: BLE001
            self.load_error = str(e) or e.__class__.__name__
        finally:
            self.loaded.set()

    def start(self):
        import sounddevice as sd

        with self.lock:
            if self.stream is not None:
                return
            self.chunks = []

            def cb(indata, frames, t, status):  # noqa: ARG001
                self.chunks.append(indata[:, 0].copy())

            self.stream = sd.InputStream(samplerate=RATE, channels=1, dtype="float32", callback=cb)
            self.stream.start()

    def stop(self):
        import numpy as np

        with self.lock:
            s, self.stream = self.stream, None
        if s is None:
            return ""
        try:
            s.stop()
            s.close()
        except Exception:
            pass
        if not self.chunks:
            diag("no audio arrived from the microphone")
            return ""
        audio = np.concatenate(self.chunks)
        self.chunks = []
        peak = float(np.abs(audio).max()) if len(audio) else 0.0
        if len(audio) < RATE * 0.35:  # a tap, not speech
            diag("too short (%.2fs)" % (len(audio) / RATE))
            return ""
        if peak < 0.003:
            diag("%.1fs recorded but it is silent (peak %.4f): microphone muted, blocked by Windows privacy, "
                 "or the wrong input device" % (len(audio) / RATE, peak))
        self.loaded.wait()
        if self.model is None:
            raise RuntimeError("speech model failed to load: %s" % self.load_error)
        segs, _ = self.model.transcribe(audio, language="en", beam_size=5, vad_filter=True,
                                        condition_on_previous_text=False)
        text = " ".join(s.text.strip() for s in segs).strip()
        diag("%.1fs, peak %.3f -> %r" % (len(audio) / RATE, peak, text))
        # Whisper's habit on near-silence
        if text.lower().strip(" .!") in ("", "you", "thank you", "thanks for watching"):
            return ""
        return text


def diag(m):
    """One line per push-to-talk on stderr (the Windows HUD copies it into ears.log)."""
    try:
        sys.stderr.write("ptt: " + m + "\n")
        sys.stderr.flush()
    except Exception:
        pass


def selftest(ears):
    import numpy as np
    import sounddevice as sd

    print("  Microphone test", flush=True)
    try:
        dev = sd.query_devices(kind="input")
        print("  Input device : %s" % dev["name"], flush=True)
    except Exception as e:  # noqa: BLE001
        print("  ! No input device: %s" % e, flush=True)
        return
    threading.Thread(target=ears.load, daemon=True).start()
    print("  Speak now for 4 seconds...", flush=True)
    try:
        rec = sd.rec(int(4 * RATE), samplerate=RATE, channels=1, dtype="float32")
        sd.wait()
    except Exception as e:  # noqa: BLE001
        print("  ! Could not record: %s" % e, flush=True)
        return
    a = rec[:, 0]
    peak = float(np.abs(a).max())
    bar = "#" * min(40, int(peak * 80))
    print("  Loudness     : %.3f  [%-40s]" % (peak, bar), flush=True)
    if peak < 0.003:
        print("  ! Silent. Check: Settings > Privacy & security > Microphone > 'Let desktop apps access", flush=True)
        print("    your microphone' is ON; the mic isn't muted; and Settings > System > Sound > Input", flush=True)
        print("    has the right microphone selected.", flush=True)
    ears.loaded.wait()
    if ears.model is None:
        print("  ! Speech model failed to load: %s" % ears.load_error, flush=True)
        return
    segs, _ = ears.model.transcribe(a, language="en", beam_size=5, vad_filter=True, condition_on_previous_text=False)
    print("  Heard        : %r" % " ".join(s.text.strip() for s in segs).strip(), flush=True)


# ---------------------------------------------------------------- Windows: driven by the HUD over stdin
def serve(ears):
    out = sys.stdout
    # Windows quirk: while this thread blocks reading the stdin pipe, any library that pokes at stdin
    # (isatty / GetFileType during the model import) blocks too. Keep a private copy of the pipe for
    # commands and point fd 0 at NUL, so the loader thread never touches the busy handle.
    cmd_fd = os.dup(0)
    null_fd = os.open(os.devnull, os.O_RDONLY)
    os.dup2(null_fd, 0)
    os.close(null_fd)
    sys.stdin = open(os.devnull, "r")
    commands = os.fdopen(cmd_fd, "r", encoding="utf-8", errors="replace")

    def say(line):
        out.write(line + "\n")
        out.flush()

    threading.Thread(target=lambda: (ears.load(), say("READY" if ears.model else "ERROR " + str(ears.load_error))),
                     daemon=True).start()
    while True:
        raw = commands.readline()
        if not raw:
            break
        cmd = raw.strip().lower()
        try:
            if cmd == "start":
                ears.start()
                say("LISTENING")
            elif cmd == "stop":
                text = ears.stop()
                say("TEXT " + base64.b64encode(text.encode("utf-8")).decode("ascii"))
            elif cmd == "quit":
                break
        except Exception as e:  # noqa: BLE001
            say("ERROR " + (str(e) or e.__class__.__name__).replace("\n", " "))
    # stdin closed (the HUD exited): leave quietly


# ---------------------------------------------------------------- macOS: listens for the key itself
TERMINALS = {
    "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
    "net.kovidgoyal.kitty", "com.github.wez.wezterm", "org.alacritty", "io.alacritty",
}


def mac(ears, state, home):
    from AppKit import NSWorkspace
    from pynput import keyboard
    import subprocess

    import fcntl

    log_path = os.path.join(home, "ears.log")

    def log(m):
        try:
            with open(log_path, "a", encoding="utf-8") as f:
                f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + m + "\n")
        except Exception:
            pass

    # one listener per Mac: two tabs opened together must not both type what you say
    lock = open(os.path.join(home, "ears.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return

    with open(os.path.join(home, "ears.pid"), "w") as f:
        f.write(str(os.getpid()))

    # Accessibility lets us type into the terminal (and see the key). Ask macOS to show its prompt once.
    try:
        from ApplicationServices import AXIsProcessTrustedWithOptions, kAXTrustedCheckOptionPrompt

        if not AXIsProcessTrustedWithOptions({kAXTrustedCheckOptionPrompt: True}):
            log("not trusted yet: allow your terminal app in System Settings > Privacy & Security > "
                "Accessibility and Input Monitoring, then reopen it")
    except Exception as e:  # noqa: BLE001
        log("accessibility check skipped: %s" % e)

    keymap = {"rightoption": keyboard.Key.alt_r, "rightalt": keyboard.Key.alt_r, "rightcmd": keyboard.Key.cmd_r,
              "rightctrl": keyboard.Key.ctrl_r, "f8": keyboard.Key.f8, "f9": keyboard.Key.f9}
    name = str(state.get("ptt_key", "rightoption")).lower().replace(" ", "").replace("_", "").replace("-", "")
    talk = keymap.get(name, keyboard.Key.alt_r)
    auto_send = state.get("ptt_auto_send", True)
    typer = keyboard.Controller()
    held = {"down": False, "active": False}

    def front_is_terminal():
        try:
            app = NSWorkspace.sharedWorkspace().frontmostApplication()
            return str(app.bundleIdentifier()) in TERMINALS
        except Exception:
            return False

    def chime(sound):
        try:
            subprocess.Popen(["afplay", "-v", "0.35", "/System/Library/Sounds/%s.aiff" % sound],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass

    def finish():
        try:
            text = ears.stop()
        except Exception as e:  # noqa: BLE001
            log("transcribe failed: %s" % e)
            chime("Basso")
            return
        if not text:
            return
        if not front_is_terminal():
            log("terminal no longer in front; dropped: %r" % text)
            return
        typer.type(text)
        if auto_send:
            time.sleep(0.08)
            typer.press(keyboard.Key.enter)
            typer.release(keyboard.Key.enter)
        chime("Pop")

    def on_press(key):
        if key != talk or held["down"]:
            return
        held["down"] = True
        if front_is_terminal():
            try:
                ears.start()
                held["active"] = True
                chime("Tink")
            except Exception as e:  # noqa: BLE001
                log("microphone failed: %s (allow your terminal app under Privacy & Security > Microphone)" % e)

    def on_release(key):
        if key != talk:
            return
        held["down"] = False
        if held["active"]:
            held["active"] = False
            threading.Thread(target=finish, daemon=True).start()

    threading.Thread(target=ears.load, daemon=True).start()
    listener = keyboard.Listener(on_press=on_press, on_release=on_release)
    listener.start()
    log("listening for %s (model %s)" % (name, ears.model_name))

    # Quit ~20 s after the last Jarvis session closes (launch.sh keeps a pid file per session).
    sessions = os.path.join(home, "sessions")
    last_seen = time.time()
    while True:
        time.sleep(3)
        alive = False
        try:
            for fn in os.listdir(sessions):
                try:
                    os.kill(int(fn), 0)
                    alive = True
                except (ValueError, ProcessLookupError):
                    try:
                        os.remove(os.path.join(sessions, fn))
                    except OSError:
                        pass
                except PermissionError:
                    alive = True
        except FileNotFoundError:
            pass
        if alive:
            last_seen = time.time()
        elif time.time() - last_seen > 20:
            break
    listener.stop()
    try:
        os.remove(os.path.join(home, "ears.pid"))
    except OSError:
        pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--state", required=True)
    ap.add_argument("--model", help="override the state file's stt_model (installer warm-up)")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--warmup", action="store_true")
    g.add_argument("--serve", action="store_true")
    g.add_argument("--mac", action="store_true")
    g.add_argument("--test", action="store_true", help="record 4 s from the default mic and show what was heard")
    a = ap.parse_args()
    home = os.path.dirname(os.path.abspath(a.state))
    state = load_state(a.state)
    ears = Ears(a.model or state.get("stt_model", "base.en"), os.path.join(home, "models"))
    if a.warmup:
        print("  Downloading the speech model (%s) - first time only..." % ears.model_name, flush=True)
        ears.load()
        if ears.model is None:
            print("ERROR " + str(ears.load_error), flush=True)
            sys.exit(1)
        import numpy as np

        list(ears.model.transcribe(np.zeros(RATE, dtype="float32"), language="en")[0])
        print("READY", flush=True)
    elif a.test:
        selftest(ears)
    elif a.serve:
        serve(ears)
    else:
        mac(ears, state, home)


if __name__ == "__main__":
    main()
