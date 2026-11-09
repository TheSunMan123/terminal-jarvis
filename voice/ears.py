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


API_ORDER = ("Windows WASAPI", "Windows DirectSound", "MME", "Windows WDM-KS")


def mic_candidates(preferred=None):
    """The default microphone as seen through each audio route ("host API"), best first.

    Some laptop mics (Intel Smart Sound arrays) give pure digital silence through the old MME route
    that PortAudio uses by default, but work through WASAPI, the route Windows itself uses.
    Returns [(api_name, device_index)]."""
    import sounddevice as sd

    devs, apis = sd.query_devices(), sd.query_hostapis()
    try:
        default_in = int(sd.query_devices(kind="input")["index"])
    except Exception:
        default_in = next((i for i, d in enumerate(devs) if d["max_input_channels"] > 0), -1)
    if default_in < 0:
        return []
    if sys.platform != "win32":
        return [(apis[devs[default_in]["hostapi"]]["name"], default_in)]
    base = devs[default_in]["name"]
    stem = base[:24].lower()   # MME cuts names at 31 characters
    out = []
    for api in API_ORDER:
        for i, d in enumerate(devs):
            if d["max_input_channels"] > 0 and apis[d["hostapi"]]["name"] == api and \
                    (d["name"].lower().startswith(stem) or base.lower().startswith(d["name"][:24].lower())):
                out.append((api, i))
                break
    if not any(i == default_in for _, i in out):
        out.append((apis[devs[default_in]["hostapi"]]["name"], default_in))
    if preferred:
        out.sort(key=lambda c: c[0] != preferred)
    return out


def to_16k(chunks, rate):
    """Join callback blocks, keep the loudest channel, resample to 16 kHz mono."""
    import numpy as np

    a = np.concatenate(chunks)
    if a.ndim == 2:
        a = a[:, int(np.abs(a).max(axis=0).argmax())]
    a = a.astype("float32")
    if rate != RATE and len(a):
        if rate % RATE == 0:   # 48 kHz -> 16 kHz: average each group of 3 (cheap low-pass)
            k = rate // RATE
            a = a[: len(a) // k * k].reshape(-1, k).mean(axis=1)
        else:
            n = int(len(a) * RATE / rate)
            a = np.interp(np.arange(n) * (rate / RATE), np.arange(len(a)), a).astype("float32")
    return a


class Ears:
    def __init__(self, model_name, models_dir, mic_api=None):
        self.model_name = model_name or "base.en"
        self.models_dir = models_dir
        self.model = None
        self.loaded = threading.Event()
        self.load_error = None
        self.chunks = []
        self.stream = None
        self.rate = RATE
        self.lock = threading.Lock()
        self.mic_api = mic_api
        self.cands = None
        self.cur = 0

    def open_stream(self, cand, cb):
        import sounddevice as sd

        api, idx = cand
        d = sd.query_devices(idx)
        rate = int(d["default_samplerate"]) or RATE
        ch = max(1, min(2, int(d["max_input_channels"])))
        s = sd.InputStream(device=idx, samplerate=rate, channels=ch, dtype="float32", callback=cb)
        s.start()
        return s, rate

    def load(self):
        try:
            from faster_whisper import WhisperModel

            import numpy as np

            os.makedirs(self.models_dir, exist_ok=True)
            model = WhisperModel(self.model_name, device="cpu", compute_type="int8", download_root=self.models_dir,
                                 cpu_threads=min(8, os.cpu_count() or 4))
            # the first transcription pays a one-off setup cost: pay it now, not on the first press
            list(model.transcribe(np.zeros(RATE, dtype="float32"), language="en", vad_filter=False,
                                  without_timestamps=True)[0])
            self.model = model
        except Exception as e:  # noqa: BLE001
            self.load_error = str(e) or e.__class__.__name__
        finally:
            self.loaded.set()

    def start(self):
        with self.lock:
            if self.stream is not None:
                return
            self.chunks = []

            def cb(indata, frames, t, status):  # noqa: ARG001
                self.chunks.append(indata.copy())

            if self.cands is None:
                self.cands = mic_candidates(self.mic_api)
            if not self.cands:
                raise RuntimeError("no microphone found")
            last = None
            for _ in range(len(self.cands)):   # a route that won't open -> the next one
                cand = self.cands[self.cur % len(self.cands)]
                try:
                    self.stream, self.rate = self.open_stream(cand, cb)
                    return
                except Exception as e:  # noqa: BLE001
                    last = e
                    diag("could not open the mic via %s: %s" % (cand[0], e))
                    self.cur += 1
            raise RuntimeError("could not open the microphone: %s" % last)

    def stop(self):
        import numpy as np

        if self.stream is not None:
            time.sleep(0.2)   # people let go a hair early: keep the end of the last word
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
        audio = to_16k(self.chunks, self.rate)
        self.chunks = []
        peak = float(np.abs(audio).max()) if len(audio) else 0.0
        route = self.cands[self.cur % len(self.cands)][0] if self.cands else "?"
        if len(audio) < RATE * 0.35:  # a tap, not speech
            diag("too short (%.2fs)" % (len(audio) / RATE))
            return ""
        if peak == 0.0 and self.cands and len(self.cands) > 1:
            # digital silence: this route is dead for this mic. Use the next one from the next press on.
            self.cur += 1
            diag("pure silence via %s; switching to %s for the next press" % (route, self.cands[self.cur % len(self.cands)][0]))
            return ""
        if peak < 0.003:
            diag("%.1fs recorded via %s but it is silent (peak %.4f): microphone muted (laptop mic-mute key?), "
                 "or the wrong input device" % (len(audio) / RATE, route, peak))
        self.loaded.wait()
        if self.model is None:
            raise RuntimeError("speech model failed to load: %s" % self.load_error)
        t0 = time.time()
        segs, _ = self.model.transcribe(audio, language="en", beam_size=1, vad_filter=True,
                                        condition_on_previous_text=False, without_timestamps=True)
        text = " ".join(s.text.strip() for s in segs).strip()
        diag("%.1fs via %s, peak %.3f, recognised in %.1fs -> %r" % (len(audio) / RATE, route, peak, time.time() - t0, text))
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


def selftest(ears, state_path):
    """Record ~3 s through each audio route for the default mic, show the loudness of each, transcribe the
    best one and remember its route in state.json (mic_api) so push-to-talk uses it first."""
    import numpy as np
    import sounddevice as sd

    print("  Microphone test", flush=True)
    try:
        cands = mic_candidates()
    except Exception as e:  # noqa: BLE001
        print("  ! Could not list microphones: %s" % e, flush=True)
        return
    if not cands:
        print("  ! No microphone found.", flush=True)
        return
    print("  Microphone   : %s" % sd.query_devices(cands[0][1])["name"], flush=True)
    try:
        print("  Speakers     : %s  (where Jarvis's voice plays)" % sd.query_devices(kind="output")["name"], flush=True)
    except Exception:
        pass
    threading.Thread(target=ears.load, daemon=True).start()
    secs = 3.0
    print("  Keep talking (count slowly from one to twenty) while it tries %d audio route(s)..." % len(cands), flush=True)
    results = []
    for api, idx in cands:
        chunks = []
        try:
            s, rate = ears.open_stream((api, idx), lambda d, f, t, st: chunks.append(d.copy()))
            time.sleep(secs)
            s.stop()
            s.close()
            a = to_16k(chunks, rate) if chunks else np.zeros(0, dtype="float32")
            peak = float(np.abs(a).max()) if len(a) else 0.0
        except Exception as e:  # noqa: BLE001
            print("    %-20s  could not open (%s)" % (api, str(e).splitlines()[0][:60]), flush=True)
            continue
        print("    %-20s  loudness %.3f  [%-30s]" % (api, peak, "#" * min(30, int(peak * 60))), flush=True)
        results.append((peak, api, a))
    if not results:
        print("  ! No audio route could open the microphone.", flush=True)
        return
    best = max(r[0] for r in results)
    # routes are listed best-first (WASAPI first); take the first one that hears about as well as the loudest,
    # so room noise doesn't steer the choice to an older route
    peak, api, a = next(r for r in results if r[0] >= max(0.003, 0.5 * best)) if best >= 0.003 else max(results, key=lambda r: r[0])
    if peak < 0.003:
        print("  ! Every route is silent. The mic is muted or switched off: check the laptop's mic-mute key", flush=True)
        print("    (often F4 or F8 with a little light), Settings > System > Sound > Input (right mic, volume up,", flush=True)
        print("    not muted), and Privacy & security > Microphone.", flush=True)
        return
    try:
        st = load_state(state_path)
        st["mic_api"] = api
        with open(state_path, "w", encoding="utf-8") as f:
            json.dump(st, f, indent=2)
        print("  Using        : %s (saved; push-to-talk will use it)" % api, flush=True)
    except Exception as e:  # noqa: BLE001
        print("  (could not save the choice: %s)" % e, flush=True)
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
    ears = Ears(a.model or state.get("stt_model", "base.en"), os.path.join(home, "models"), state.get("mic_api"))
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
        selftest(ears, a.state)
    elif a.serve:
        serve(ears)
    else:
        mac(ears, state, home)


if __name__ == "__main__":
    main()
