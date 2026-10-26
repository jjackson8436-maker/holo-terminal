"""Publishes another Claude account's plan usage for the Holo Terminal watch face, without a Claude Code window.

statusline.py only sees the account a running Claude Code session is signed into. This one checks any
account on a schedule: it sends one tiny `claude -p` request (about 600 tokens) under that account's own
Claude Code config folder, reads the rate_limit_event Claude Code prints (five_hour / seven_day
utilization and reset times, account-wide), and writes them to that account's secret gist in the same
format statusline.py uses, so the watch face reads it unchanged.

  python poll.py era --setup [--config-dir DIR]   create the gist, copy this script, add a 15-minute task
  python poll.py era                              one check + push (what the task runs)

Sign the account in once first:  set CLAUDE_CONFIG_DIR=%USERPROFILE%\\.claude-era  then  claude auth login
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HOME = os.path.expanduser("~")
DIR = os.path.join(HOME, ".claude-usage", "accounts")
NO_WINDOW = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
PING = ["-p", "--model", "haiku", "--output-format", "stream-json", "--verbose",
        "--system-prompt", "Reply with: ok", "--tools", "", "--strict-mcp-config",
        "--no-session-persistence", "--setting-sources", ""]


def run(cmd, env=None, stdin=None):
    return subprocess.run(cmd, input=stdin, capture_output=True, text=True, encoding="utf-8",
                          env=env, creationflags=NO_WINDOW, timeout=120)


def claude_env(config_dir):
    env = dict(os.environ, CLAUDE_CONFIG_DIR=config_dir)
    env.pop("ANTHROPIC_API_KEY", None)      # must use the plan sign-in, never an API key
    return env


def signed_in_email(config_dir):
    p = run([shutil.which("claude") or "claude", "auth", "status"], env=claude_env(config_dir))
    try:    # tolerate any notice printed around the JSON
        st = json.loads(p.stdout[p.stdout.index("{"):p.stdout.rindex("}") + 1])
    except ValueError:
        return None
    return st.get("email") if st.get("loggedIn") else None


def log(name, msg):
    with open(os.path.join(DIR, f"{name}.log"), "a", encoding="utf-8") as f:
        f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + msg + "\n")


def check(name):
    cfg = json.load(open(os.path.join(DIR, f"{name}.json")))
    email = signed_in_email(cfg["config_dir"])
    if email != cfg["email"]:
        # Never publish some other account's numbers under this name.
        return log(name, f"SKIPPED: {cfg['config_dir']} is signed in as {email!r}, expected {cfg['email']!r}")
    p = run([shutil.which("claude") or "claude", *PING], env=claude_env(cfg["config_dir"]), stdin="ok")
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
    body = json.dumps({"files": {"usage.json": {"content": json.dumps(payload)}}})
    g = run(["gh", "api", "-X", "PATCH", f"gists/{cfg['gist_id']}", "--input", "-"], stdin=body)
    log(name, f"session {payload['five_hour']}% week {payload['seven_day']}%"
              + ("" if g.returncode == 0 else f" PUSH FAILED: {g.stderr.strip()[:300]}"))


def setup(name, config_dir):
    if shutil.which("gh") is None:
        sys.exit("The GitHub CLI (gh) isn't installed: winget install GitHub.cli, then gh auth login --scopes gist")
    email = signed_in_email(config_dir)
    if not email:
        sys.exit(f"Nothing is signed in under {config_dir}. In a terminal run:\n"
                 f"  set CLAUDE_CONFIG_DIR={config_dir}\n  claude auth login")
    os.makedirs(DIR, exist_ok=True)
    path = os.path.join(DIR, f"{name}.json")
    if os.path.exists(path):
        gist_id = json.load(open(path))["gist_id"]
        print(f"Using the existing gist {gist_id}")
    else:
        tmp = os.path.join(tempfile.mkdtemp(), "usage.json")
        with open(tmp, "w") as f:
            json.dump({"five_hour": None, "seven_day": None, "five_reset": None, "seven_reset": None,
                       "updated": int(time.time())}, f)
        p = run(["gh", "gist", "create", tmp, "--desc", f"Claude usage ({name}) for the Holo Terminal watch face"])
        if p.returncode:
            sys.exit(p.stderr)
        gist_id = p.stdout.strip().splitlines()[-1].rstrip("/").split("/")[-1]
    with open(path, "w") as f:
        json.dump({"gist_id": gist_id, "config_dir": config_dir, "email": email}, f, indent=2)

    script = os.path.join(DIR, "poll.py")
    shutil.copy(os.path.abspath(__file__), script)
    pyw = os.path.join(os.path.dirname(sys.executable), "pythonw.exe")
    task = f"Claude usage - {name}"
    p = run(["schtasks", "/Create", "/F", "/SC", "MINUTE", "/MO", "15", "/TN", task,
             "/TR", f'"{pyw}" "{script}" {name}'])
    print(p.stdout.strip() or p.stderr.strip())
    check(name)
    user = run(["gh", "api", "user", "--jq", ".login"]).stdout.strip()
    print(f"Account: {email}\nTask: {task} (every 15 minutes)\nLog: {os.path.join(DIR, name + '.log')}")
    print(f"Watch URL: https://gist.githubusercontent.com/{user}/{gist_id}/raw/usage.json")


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args or args[0].startswith("-"):
        sys.exit(__doc__)
    name = args[0]
    if "--setup" in args:
        i = args.index("--config-dir") if "--config-dir" in args else -1
        setup(name, args[i + 1] if i >= 0 else os.path.join(HOME, f".claude-{name}"))
    else:
        check(name)
