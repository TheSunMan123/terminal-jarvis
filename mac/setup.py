# /// script
# requires-python = ">=3.10,<3.13"
# dependencies = ["pillow"]
# ///
"""Terminal Jarvis for Codex - macOS setup (run by mac/install.sh; `--uninstall` undoes everything).

What it changes (all marked, everything else in these files is kept):
  ~/.codex/AGENTS.md        persona block between terminal-jarvis markers
  ~/.codex/config.toml      [tui] status_line (model, 5-hour + weekly limits, context, folder)
  ~/.codex/hooks.json       a Stop hook that reads the start of each reply aloud
  ~/.zshrc (+ bash files)   a small `codex` function that opens Codex as Jarvis
  iTerm2 Dynamic Profile    "<Assistant> · Codex" colours + backdrop (if iTerm2 is installed)
  Keychain                  your Fish Audio key, if you give one (never written to a file)
  ~/.terminal-jarvis        the kit, the backdrop, the speech model, settings
"""
import argparse
import datetime as dt
import getpass
import json
import os
import re
import shlex
import shutil
import subprocess
import sys

HOME = os.path.expanduser("~")
TJ = os.path.join(HOME, ".terminal-jarvis")
CODEX_DIR = os.path.join(HOME, ".codex")
STATE = os.path.join(TJ, "state.json")
MARK = "# terminal-jarvis"
ITERM_DIR = os.path.join(HOME, "Library", "Application Support", "iTerm2", "DynamicProfiles")
ITERM_FILE = os.path.join(ITERM_DIR, "terminal-jarvis.json")
PROFILE_GUID = "7d3a2f4e-5b1c-4c8e-9a6d-1f0e2b3c4d5e"
JARVIS_VOICE = "05b36da8574341d0803391491850db20"   # public "Jarvis" voice on fish.audio
KEY_SLOT = "terminal-jarvis-fish"
RC_START, RC_END = "# >>> terminal-jarvis >>>", "# <<< terminal-jarvis <<<"
RC_BLOCK = (RC_START + "  (typing codex opens Jarvis; removed by ~/.terminal-jarvis/mac/uninstall.sh)\n"
            'codex() { "$HOME/.terminal-jarvis/mac/launch.sh" "$@"; }\n' + RC_END + "\n")
AGENTS_RE = re.compile(r"\n?<!-- terminal-jarvis:start -->.*?<!-- terminal-jarvis:end -->\n?", re.S)
RC_RE = re.compile(r"\n?" + re.escape(RC_START) + r".*?" + re.escape(RC_END) + r"\n?", re.S)

CY, GOLD, DIM, GREEN, YEL, OFF = "\033[96m", "\033[93m", "\033[90m", "\033[92m", "\033[33m", "\033[0m"


def say(t, c=CY):
    print(c + t + OFF, flush=True)


def ask(q, default=""):
    try:
        a = input("%s%s: " % (q, " [%s]" % default if default else "")).strip()
    except EOFError:
        a = ""
    return a or default


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return ""


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def backup(path):
    if os.path.exists(path):
        shutil.copy2(path, os.path.join(TJ, os.path.basename(path) + ".backup"))


def load_state():
    try:
        with open(STATE, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


# ---------------------------------------------------------------- persona
def set_persona(user, assistant, address):
    agents = os.path.join(CODEX_DIR, "AGENTS.md")
    persona = read(os.path.join(TJ, "persona.md"))
    persona = persona.replace("{{ASSISTANT}}", assistant).replace("{{USER}}", user).replace("{{ADDRESS}}", address)
    block = "<!-- terminal-jarvis:start -->\n" + persona.strip() + "\n<!-- terminal-jarvis:end -->"
    backup(agents)
    existing = AGENTS_RE.sub("\n", read(agents)).strip()
    write(agents, (existing + "\n\n" + block + "\n") if existing else block + "\n")


def remove_persona():
    agents = os.path.join(CODEX_DIR, "AGENTS.md")
    if not os.path.exists(agents):
        return
    t = AGENTS_RE.sub("\n", read(agents)).strip()
    if t:
        write(agents, t + "\n")
    else:
        os.remove(agents)


# ---------------------------------------------------------------- status line (config.toml)
def set_status_line(state):
    cfg = os.path.join(CODEX_DIR, "config.toml")
    items = '["model-with-reasoning", "five-hour-limit", "weekly-limit", "context-remaining", "current-dir"]'
    line = "status_line = %s  %s" % (items, MARK)
    lines = read(cfg).splitlines()
    backup(cfg)
    tui = next((i for i, l in enumerate(lines) if l.strip() == "[tui]"), -1)
    out = []
    if tui < 0:
        out = lines + ["", "[tui]", line]
    else:
        end = next((i for i in range(tui + 1, len(lines)) if lines[i].lstrip().startswith("[")), len(lines))
        for i, l in enumerate(lines):
            if tui < i < end and re.match(r"^\s*status_line\s*=", l):
                if MARK not in l:
                    state["previous_status_line"] = l
                continue
            out.append(l)
            if i == tui:
                out.append(line)
    write(cfg, "\n".join(out) + "\n")


def remove_status_line(state):
    cfg = os.path.join(CODEX_DIR, "config.toml")
    if not os.path.exists(cfg):
        return
    out = []
    for l in read(cfg).splitlines():
        if MARK in l:
            if state.get("previous_status_line"):
                out.append(state["previous_status_line"])
            continue
        out.append(l)
    write(cfg, "\n".join(out) + "\n")


# ---------------------------------------------------------------- voice hook (hooks.json)
def set_hook(command):
    path = os.path.join(CODEX_DIR, "hooks.json")
    if command:
        backup(path)
    try:
        data = json.loads(read(path) or "{}")
    except ValueError:
        data = {}
    hooks = data.setdefault("hooks", {})
    stop = [h for h in hooks.get("Stop", []) if "terminal-jarvis" not in json.dumps(h)]
    if command:
        stop.append({"hooks": [{"type": "command", "command": command, "timeout": 15}]})
    hooks["Stop"] = stop
    write(path, json.dumps(data, indent=2) + "\n")


# ---------------------------------------------------------------- shell function
def rc_files():
    files = [os.path.join(HOME, ".zshrc")]          # zsh is the macOS default shell
    for f in (".bashrc", ".bash_profile"):
        p = os.path.join(HOME, f)
        if os.path.exists(p):
            files.append(p)
    return files


def set_rc():
    for p in rc_files():
        t = RC_RE.sub("\n", read(p)).rstrip()
        write(p, (t + "\n\n" if t else "") + RC_BLOCK)


def remove_rc():
    for f in (".zshrc", ".bashrc", ".bash_profile"):
        p = os.path.join(HOME, f)
        if os.path.exists(p) and RC_START in read(p):
            write(p, RC_RE.sub("\n", read(p)).strip() + "\n")


# ---------------------------------------------------------------- backdrop + iTerm2 profile
def font(names, size):
    from PIL import ImageFont

    for n in names:
        try:
            return ImageFont.truetype(n, size)
        except Exception:
            continue
    return ImageFont.load_default()


def render_backdrop(assistant):
    from PIL import Image, ImageDraw

    base = Image.open(os.path.join(TJ, "assets", "backdrop-base.png")).convert("RGBA")
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    letters = assistant.upper().replace(" ", "")
    title = (".".join(letters) + ".") if len(letters) <= 8 else assistant.upper()
    f_title = font(["/System/Library/Fonts/Supplemental/DIN Alternate Bold.ttf", "/System/Library/Fonts/Helvetica.ttc"], 26)
    f_mono = font(["/System/Library/Fonts/Menlo.ttc", "/System/Library/Fonts/Monaco.ttf"], 14)
    tx, ty = 1600, 1290   # under the J art (same spot as the Windows backdrop)
    d.text((tx, ty - 36), title, font=f_title, fill=(246, 236, 222, 150))
    d.text((tx, ty), "NEURAL LINK  //  ACTIVE   ·   CODEX CHANNEL", font=f_mono, fill=(255, 194, 92, 120))
    d.ellipse((tx - 20, ty + 4, tx - 11, ty + 13), fill=(255, 77, 61, 190))
    out = Image.alpha_composite(base, layer).convert("RGB")
    for f in os.listdir(TJ):
        if f.startswith("backdrop-") and f.endswith(".png"):
            os.remove(os.path.join(TJ, f))
    path = os.path.join(TJ, "backdrop-%s.png" % dt.datetime.now().strftime("%Y%m%d%H%M%S"))   # new name: iTerm caches images
    out.save(path)
    return path, title


def rgb(hexstr):
    h = hexstr.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return {"Red Component": r, "Green Component": g, "Blue Component": b, "Alpha Component": 1, "Color Space": "sRGB"}


# colours taken from the J art: navy ground, warm white text, gold cursor, arc-reactor cyan, armour red
PALETTE = ["#0B1A2B", "#FF4D3D", "#5FD6A8", "#FFC247", "#4AA8FF", "#E07BFF", "#3FD8FF", "#E6EDF5",
           "#6B8299", "#FF8070", "#8CF0C8", "#FFDC8A", "#8CCBFF", "#EFB0FF", "#9BEBFF", "#FFFFFF"]
BG, FG, CURSOR, SELECTION = "#06101B", "#EAF1F8", "#FFC247", "#5A2A1E"


def set_iterm(profile_name, backdrop):
    if not (os.path.isdir("/Applications/iTerm.app") or os.path.isdir(os.path.join(HOME, "Applications", "iTerm.app"))):
        return False
    prof = {
        "Name": profile_name, "Guid": PROFILE_GUID, "Tags": ["Terminal Jarvis"],
        "Background Color": rgb(BG), "Foreground Color": rgb(FG), "Bold Color": rgb("#FFFFFF"),
        "Cursor Color": rgb(CURSOR), "Cursor Text Color": rgb(BG), "Selection Color": rgb(SELECTION),
        "Selected Text Color": rgb(FG), "Link Color": rgb("#3FD8FF"), "Cursor Type": 2,
        "Background Image Location": backdrop, "Background Image Mode": 2, "Blend": 0.0, "Transparency": 0,
    }
    for i, c in enumerate(PALETTE):
        prof["Ansi %d Color" % i] = rgb(c)
    write(ITERM_FILE, json.dumps({"Profiles": [prof]}, indent=2) + "\n")
    return True


# ---------------------------------------------------------------- keychain
def keychain_write(secret):
    subprocess.run(["security", "add-generic-password", "-U", "-s", KEY_SLOT, "-a", "fish-audio", "-w", secret],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def keychain_has():
    return subprocess.run(["security", "find-generic-password", "-s", KEY_SLOT], stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode == 0


# ---------------------------------------------------------------- state files
def save_state(state):
    write(STATE, json.dumps(state, indent=2) + "\n")
    env = {"TJ_CODEX": state.get("codex_exe", ""), "TJ_UV": state.get("uv_exe", ""),
           "TJ_ASSISTANT": state.get("assistant", "Jarvis"), "TJ_ADDRESS": state.get("address", "sir"),
           "TJ_PROFILE": state.get("profile_name", ""), "TJ_VOICE": state.get("voice", "none"),
           "TJ_PTT_KEY": state.get("ptt_key", "none")}
    write(os.path.join(TJ, "state.env"), "".join("%s=%s\n" % (k, shlex.quote(str(v))) for k, v in env.items()))


# ---------------------------------------------------------------- install / uninstall
def install(a):
    state = load_state()   # a re-run keeps earlier answers as defaults (and the original status line for uninstall)
    user = a.user or ask("  Your name", state.get("user") or getpass.getuser())
    assistant = a.assistant or ask("  Your assistant's name", state.get("assistant", "Jarvis"))
    assistant = re.sub(r"[^\w \-]", "", assistant).strip() or "Jarvis"
    address = a.address or ask("  How should %s address you (sir, ma'am, boss, your name...)" % assistant,
                               state.get("address", "sir"))
    profile_name = "%s · Codex" % assistant
    state.update({"user": user, "assistant": assistant, "address": address, "codex_exe": a.codex,
                  "uv_exe": a.uv, "profile_name": profile_name, "installed": dt.datetime.now().isoformat(timespec="seconds"),
                  "platform": "mac"})

    set_persona(user, assistant, address)
    say("  + Persona: %s - applies to EVERY Codex session on this Mac (terminal and Codex app)" % assistant, GREEN)
    set_status_line(state)
    say("  + Status bar: model, 5-hour limit, weekly limit, context left, folder", GREEN)

    backdrop, title = render_backdrop(assistant)
    if set_iterm(profile_name, backdrop):
        state["iterm"] = True
        say("  + iTerm2 profile '%s' with the Jarvis colours and backdrop (%s)" % (profile_name, title), GREEN)
    else:
        state["iterm"] = False
        say("  + Colours: set while Jarvis runs. For the full backdrop install iTerm2 (iterm2.com) and re-run.", GREEN)

    set_rc()
    say("  + Type 'codex' in a new terminal window and %s opens (scripts like 'codex exec' stay plain Codex)" % assistant, GREEN)

    # voice
    voice = (a.voice or "").lower()
    if not voice:
        say("")
        say("  VOICE: %s reads the start of every reply aloud." % assistant)
        say("    For the real Jarvis voice, paste a Fish Audio API key (free account at fish.audio -> API Keys).")
        say("    Press Return to use the built-in British macOS voice (Daniel) instead. Type 'none' for silent.", DIM)
        key = getpass.getpass("  Fish Audio API key (hidden as you paste): ").strip()
        if key.lower() == "none":
            voice = "none"
        elif key:
            keychain_write(key)
            voice = "fish"
            say("    Key saved in your macOS Keychain (never written to a file).", DIM)
        else:
            voice = "fish" if keychain_has() and state.get("voice") == "fish" else "mac"
    if voice not in ("fish", "mac", "none"):
        voice = "mac"
    state["voice"] = voice
    if voice == "fish":
        state.setdefault("fish_voice_id", JARVIS_VOICE)
        state.setdefault("fish_model", "s2.1-pro-free")
        state["fish_key_slot"] = KEY_SLOT
    state.setdefault("mac_voice", "Daniel")
    speak = os.path.join(TJ, "mac", "speak.py")
    hook = "%s run --quiet --script %s" % (shlex.quote(a.uv), shlex.quote(speak)) if voice != "none" else None
    set_hook(hook)
    if hook:   # build the voice helper's environment now, so the first reply isn't slow
        subprocess.run([a.uv, "run", "--quiet", "--script", speak, "--check"], stdout=subprocess.DEVNULL)
    say("  + Voice: %s" % {"fish": "Fish Audio (Jarvis voice)", "mac": "macOS Daniel", "none": "off"}[voice], GREEN)

    # push-to-talk
    key = (a.ptt_key or "").lower()
    if not key:
        say("")
        say("  Push-to-talk: hold a key while a terminal is in front and speak; let go and it's typed into Codex and sent.")
        say("    Speech is recognised on this Mac (a local Whisper model, ~150 MB download). Audio never leaves it.", DIM)
        say("    rightoption (default) / rightcmd / f8 / f9 / none", DIM)
        key = ask("  Talk key", state.get("ptt_key", "rightoption")).lower()
    if key not in ("rightoption", "rightcmd", "rightctrl", "f8", "f9", "none"):
        key = "rightoption"
    state["ptt_key"] = key
    state["ptt_auto_send"] = True
    if key != "none":
        state["stt_model"] = a.stt_model or state.get("stt_model", "base.en")
        say("  Downloading the speech engine + model (%s; a minute or two the first time)..." % state["stt_model"], DIM)
        r = subprocess.run([a.uv, "run", "--quiet", "--script", os.path.join(TJ, "voice", "ears.py"), "--warmup",
                            "--model", state["stt_model"], "--state", STATE])
        if r.returncode != 0:
            say("  ! Speech engine setup failed; push-to-talk is off. Re-run the installer to retry.", YEL)
            state["ptt_key"] = "none"
        else:
            say("  + Push-to-talk: hold %s (see the one-time permissions below)" % key.upper(), GREEN)

    save_state(state)
    if state["ptt_key"] != "none":
        # ask for the permissions NOW, from this terminal, so macOS attributes them to the terminal app
        # (a background process often never gets its prompts shown, which is how push-to-talk ended up silent)
        say("")
        say("  Push-to-talk permissions: macOS will ask now. Click Allow, and switch this terminal app ON in the", YEL)
        say("  Accessibility and Input Monitoring lists when System Settings opens.", YEL)
        subprocess.run([a.uv, "run", "--quiet", "--script", os.path.join(TJ, "voice", "ears.py"), "--permissions",
                        "--state", STATE])
    say("")
    say("  %s is online, %s. Open a NEW terminal window (or tab) and type  codex" % (assistant, address), "\033[97m")
    say("  ONE-TIME STEPS:", YEL)
    n = 1
    if voice != "none":
        say("   %d. Voice: in Codex type  /hooks  and trust the Terminal Jarvis 'Stop' hook (Codex asks before running new hooks)." % n, YEL)
        n += 1
    if state["ptt_key"] != "none":
        say("   %d. Push-to-talk: the first time you hold the key, macOS asks for permissions for your terminal app" % n, YEL)
        say("      (Terminal or iTerm2). Allow the Microphone, then in System Settings > Privacy & Security turn it on", YEL)
        say("      under Accessibility AND Input Monitoring. Anything missing? Run (in that same terminal app):", YEL)
        say("        bash ~/.terminal-jarvis/mac/permissions.sh", YEL)
    if not state["iterm"]:
        say("  Tip: in iTerm2 you also get the backdrop with the J. Terminal.app gets the colours only.", DIM)
    say("  Undo everything:  bash ~/.terminal-jarvis/mac/uninstall.sh", DIM)
    say("")


def uninstall():
    state = load_state()
    remove_persona()
    remove_status_line(state)
    if os.path.exists(os.path.join(CODEX_DIR, "hooks.json")):
        set_hook(None)
    remove_rc()
    if os.path.exists(ITERM_FILE):
        os.remove(ITERM_FILE)
    if state.get("fish_key_slot") == KEY_SLOT:
        subprocess.run(["security", "delete-generic-password", "-s", KEY_SLOT], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
    print("  Terminal Jarvis settings removed.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--codex")
    ap.add_argument("--uv")
    ap.add_argument("--user")
    ap.add_argument("--assistant")
    ap.add_argument("--address")
    ap.add_argument("--voice", help="fish|mac|none")
    ap.add_argument("--ptt-key", dest="ptt_key")
    ap.add_argument("--stt-model", dest="stt_model", help="tiny.en|base.en|small.en")
    ap.add_argument("--uninstall", action="store_true")
    a = ap.parse_args()
    if a.uninstall:
        uninstall()
        return
    if not a.codex or not a.uv:
        sys.exit("run mac/install.sh instead")
    os.makedirs(TJ, exist_ok=True)
    install(a)


if __name__ == "__main__":
    main()
