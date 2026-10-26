"""Watches another Claude account's plan usage on a schedule, without a Claude Code window.

statusline.py only sees the account a running Claude Code session is signed into. This one checks any
account: it sends one tiny `claude -p` request (about 600 tokens) under that account's own Claude Code
config folder and reads the rate_limit_event Claude Code prints (five_hour / seven_day utilization and
reset times, account-wide). Then it can:

  - send a phone notification through ntfy.sh when a limit passes 50%, 80% or 100%
    (once per threshold per block/week; a Garmin mirrors it from the phone), and/or
  - write the numbers to a secret gist in statusline.py's format, for the watch face.

  python poll.py era --setup --ntfy TOPIC [--gist] [--config-dir DIR]
  python poll.py era            one check (what the 15-minute scheduled task runs)
  python poll.py era --test     send a test notification

Sign the account in once first:  set CLAUDE_CONFIG_DIR=%USERPROFILE%\\.claude-era  then  claude auth login
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

HOME = os.path.expanduser("~")
DIR = os.path.join(HOME, ".claude-usage", "accounts")
NO_WINDOW = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
PING = ["-p", "--model", "haiku", "--output-format", "stream-json", "--verbose",
        "--system-prompt", "Reply with: ok", "--tools", "", "--strict-mcp-config",
        "--no-session-persistence", "--setting-sources", ""]
THRESHOLDS = (50, 80, 100)
# A scheduled task may not have ~/.local/bin on PATH, so look there too.
CLAUDE = shutil.which("claude") or next((p for p in (os.path.join(HOME, ".local", "bin", "claude.exe"),
                                                     os.path.join(HOME, ".local", "bin", "claude"))
                                          if os.path.exists(p)), "claude")
LABELS = {"five_hour": "5-hour block", "seven_day": "weekly limit"}


def run(cmd, env=None, stdin=None):
    return subprocess.run(cmd, input=stdin, capture_output=True, text=True, encoding="utf-8",
                          env=env, creationflags=NO_WINDOW, timeout=120)


def claude_env(config_dir):
    env = dict(os.environ, CLAUDE_CONFIG_DIR=config_dir)
    env.pop("ANTHROPIC_API_KEY", None)      # must use the plan sign-in, never an API key
    return env


def signed_in_email(config_dir):
    p = run([CLAUDE, "auth", "status"], env=claude_env(config_dir))
    try:    # tolerate any notice printed around the JSON
        st = json.loads(p.stdout[p.stdout.index("{"):p.stdout.rindex("}") + 1])
    except ValueError:
        return None
    return st.get("email") if st.get("loggedIn") else None


def log(name, msg):
    with open(os.path.join(DIR, f"{name}.log"), "a", encoding="utf-8") as f:
        f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + msg + "\n")


def load(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def notify(topic, title, message, priority="default"):
    req = urllib.request.Request(f"https://ntfy.sh/{topic}", data=message.encode("utf-8"),
                                 headers={"Title": title, "Priority": priority, "Tags": "robot"})
    urllib.request.urlopen(req, timeout=20).read()


def alerts(name, cfg, win):
    """Notify once per threshold crossed, per block/week (a new reset time starts it over)."""
    path = os.path.join(DIR, f"{name}.alerts.json")
    state = load(path, {})
    for key, label in LABELS.items():
        w = win.get(key) or {}
        if w.get("utilization") is None:
            continue
        pct = w["utilization"] * 100
        s = state.get(key, {})
        if s.get("resets") != w.get("resetsAt"):
            s = {"resets": w.get("resetsAt"), "sent": 0}
        hit = max([t for t in THRESHOLDS if pct >= t], default=0)
        if hit > s["sent"]:
            when = time.strftime("%a %I:%M %p", time.localtime(w["resetsAt"])) if w.get("resetsAt") else "?"
            try:
                notify(cfg["ntfy"], f"{cfg.get('label', name)} Claude: {label} {round(pct)}%",
                       f"{label} is at {round(pct)}%. Resets {when}.",
                       "high" if hit >= 100 else "default")
                s["sent"] = hit
                log(name, f"ALERT {key} {round(pct)}% (threshold {hit})")
            except OSError as e:
                log(name, f"ALERT FAILED {key}: {e}")
        state[key] = s
    with open(path, "w") as f:
        json.dump(state, f)


def check(name):
    cfg = load(os.path.join(DIR, f"{name}.json"), None)
    email = signed_in_email(cfg["config_dir"])
    if email != cfg["email"]:
        # Never report some other account's numbers under this name.
        return log(name, f"SKIPPED: {cfg['config_dir']} is signed in as {email!r}, expected {cfg['email']!r}")
    p = run([CLAUDE, *PING], env=claude_env(cfg["config_dir"]), stdin="ok")
    win = None
    for line in p.stdout.splitlines():
        try:
            o = json.loads(line)
        except ValueError:
            continue
        if o.get("type") == "rate_limit_event":
            win = (o.get("rate_limit_info") or {}).get("unifiedWindows")
    if not win:
        return log(name, f"FAILED: no rate_limit_event (exit {p.returncode}) {p.stderr.strip()[:300]}")
    five, week = win.get("five_hour") or {}, win.get("seven_day") or {}
    pct = lambda w: None if w.get("utilization") is None else round(w["utilization"] * 100, 1)
    payload = {"five_hour": pct(five), "seven_day": pct(week),
               "five_reset": five.get("resetsAt"), "seven_reset": week.get("resetsAt"),
               "updated": int(time.time())}
    note = ""
    if cfg.get("gist_id"):
        body = json.dumps({"files": {"usage.json": {"content": json.dumps(payload)}}})
        g = run(["gh", "api", "-X", "PATCH", f"gists/{cfg['gist_id']}", "--input", "-"], stdin=body)
        note = "" if g.returncode == 0 else f" GIST PUSH FAILED: {g.stderr.strip()[:300]}"
    log(name, f"session {payload['five_hour']}% week {payload['seven_day']}%{note}")
    page(name, cfg, payload)
    if cfg.get("ntfy"):
        alerts(name, cfg, win)


def page(name, cfg, payload):
    """Keep 8 days of checks and redraw <name>.html: both limits now plus a 24-hour chart."""
    hpath = os.path.join(DIR, f"{name}.history.json")
    hist = [h for h in load(hpath, []) if h["t"] > payload["updated"] - 8 * 86400]
    hist.append({"t": payload["updated"], "s": payload["five_hour"], "w": payload["seven_day"]})
    with open(hpath, "w") as f:
        json.dump(hist, f)

    W, H, now = 640, 200, payload["updated"]
    day = [h for h in hist if h["t"] > now - 86400]
    x = lambda t: round((t - (now - 86400)) / 86400 * W, 1)
    y = lambda v: round(H - min(v or 0, 100) / 100 * H, 1)
    line = lambda k: " ".join(f"{x(h['t'])},{y(h[k])}" for h in day if h[k] is not None)
    grid = "".join(f'<line x1="0" x2="{W}" y1="{y(v)}" y2="{y(v)}" class="g"/>'
                   f'<text x="4" y="{y(v) - 3}" class="l">{v}%</text>' for v in (50, 80, 100))
    when = lambda t: time.strftime("%a %I:%M %p", time.localtime(t)) if t else "?"

    def meter(label, v, reset):
        v = v or 0
        cls = "hot" if v >= 80 else "warm" if v >= 50 else ""
        return (f'<div class="card"><div class="k">{label}</div><div class="v {cls}">{round(v)}%</div>'
                f'<div class="bar"><i class="{cls}" style="width:{min(v, 100)}%"></i></div>'
                f'<div class="k">resets {when(reset)}</div></div>')

    title = f"{cfg.get('label', name)} Claude usage"
    html = f"""<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="refresh" content="300">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>{title}</title><style>
:root{{--bg:#f6f7f9;--card:#fff;--fg:#1d2330;--mut:#6b7280;--a:#2563eb;--b:#9333ea;--warm:#d97706;--hot:#dc2626;--g:#e5e7eb}}
@media (prefers-color-scheme:dark){{:root{{--bg:#0f1115;--card:#181b22;--fg:#e6e8ee;--mut:#9aa1ad;--a:#60a5fa;--b:#c084fc;--warm:#f59e0b;--hot:#f87171;--g:#2a2f3a}}}}
body{{margin:0;padding:16px;background:var(--bg);color:var(--fg);font:15px system-ui,sans-serif}}
main{{max-width:680px;margin:auto}} h1{{font-size:20px;margin:0 0 4px}} .k{{color:var(--mut);font-size:13px}}
.row{{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin:14px 0}} .card{{background:var(--card);border-radius:12px;padding:14px}}
.v{{font-size:40px;font-weight:700;margin:4px 0}} .bar{{height:8px;background:var(--g);border-radius:4px;margin:6px 0}}
.bar i{{display:block;height:100%;border-radius:4px;background:var(--a)}} .warm{{color:var(--warm)}} .hot{{color:var(--hot)}}
.bar i.warm{{background:var(--warm)}} .bar i.hot{{background:var(--hot)}}
svg{{width:100%;height:auto;display:block}} .g{{stroke:var(--g)}} .l{{fill:var(--mut);font-size:11px}}
.s{{fill:none;stroke:var(--a);stroke-width:2}} .w{{fill:none;stroke:var(--b);stroke-width:2}}
.key span{{margin-right:14px}} .key b{{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:4px}}
</style></head><body><main><h1>{title}</h1><div class="k">{cfg['email']} · checked {when(now)} · refreshes every 15 min</div>
<div class="row">{meter("5-hour block", payload["five_hour"], payload["five_reset"])}{meter("Weekly limit", payload["seven_day"], payload["seven_reset"])}</div>
<div class="card"><div class="k key">Last 24 hours &nbsp; <span><b style="background:var(--a)"></b>5-hour</span><span><b style="background:var(--b)"></b>weekly</span></div>
<svg viewBox="0 0 {W} {H}">{grid}<polyline class="s" points="{line('s')}"/><polyline class="w" points="{line('w')}"/></svg></div>
<p class="k" id="stale"></p></main><script>
if (Date.now()/1000 - {now} > 2400) document.getElementById('stale').textContent = 'No check for over 40 minutes - is this PC asleep or signed out?';
</script></body></html>"""
    with open(os.path.join(DIR, f"{name}.html"), "w", encoding="utf-8") as f:
        f.write(html)


def make_gist(name):
    if shutil.which("gh") is None:
        sys.exit("--gist needs the GitHub CLI: winget install GitHub.cli, then gh auth login --scopes gist")
    tmp = os.path.join(tempfile.mkdtemp(), "usage.json")
    with open(tmp, "w") as f:
        json.dump({"five_hour": None, "seven_day": None, "five_reset": None, "seven_reset": None,
                   "updated": int(time.time())}, f)
    p = run(["gh", "gist", "create", tmp, "--desc", f"Claude usage ({name}) for the Holo Terminal watch face"])
    if p.returncode:
        sys.exit(p.stderr)
    return p.stdout.strip().splitlines()[-1].rstrip("/").split("/")[-1]


def setup(name, config_dir, ntfy, gist):
    email = signed_in_email(config_dir)
    if not email:
        sys.exit(f"Nothing is signed in under {config_dir}. In a terminal run:\n"
                 f"  set CLAUDE_CONFIG_DIR={config_dir}\n  claude auth login")
    os.makedirs(DIR, exist_ok=True)
    path = os.path.join(DIR, f"{name}.json")
    cfg = load(path, {})
    cfg.update({"config_dir": config_dir, "email": email, "label": cfg.get("label", name.upper())})
    if ntfy:
        cfg["ntfy"] = ntfy
    if gist and not cfg.get("gist_id"):
        cfg["gist_id"] = make_gist(name)
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2)

    script = os.path.join(DIR, "poll.py")
    shutil.copy(os.path.abspath(__file__), script)
    pyw = os.path.join(os.path.dirname(sys.executable), "pythonw.exe")
    task = f"Claude usage - {name}"
    p = run(["schtasks", "/Create", "/F", "/SC", "MINUTE", "/MO", "15", "/TN", task,
             "/TR", f'"{pyw}" "{script}" {name}'])
    print(p.stdout.strip() or p.stderr.strip())
    check(name)
    print(f"Account: {email}\nTask: {task} (every 15 minutes)\nLog: {os.path.join(DIR, name + '.log')}")


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args or args[0].startswith("-"):
        sys.exit(__doc__)
    name = args[0]
    opt = lambda flag: args[args.index(flag) + 1] if flag in args else None
    if "--setup" in args:
        setup(name, opt("--config-dir") or os.path.join(HOME, f".claude-{name}"), opt("--ntfy"), "--gist" in args)
    elif "--test" in args:
        cfg = load(os.path.join(DIR, f"{name}.json"), {})
        notify(cfg["ntfy"], f"{cfg.get('label', name)} Claude: test", "Usage alerts are set up.")
        print("sent")
    else:
        try:
            check(name)
        except Exception as e:      # pythonw has no console; make failures visible in the log
            log(name, f"ERROR {type(e).__name__}: {e}")
