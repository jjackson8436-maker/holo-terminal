"""Claude Code status line that shows plan usage and publishes it for the Holo Terminal watch face.

Claude Code pipes session JSON on stdin; for Pro/Max plans it carries
rate_limits.five_hour / seven_day {used_percentage, resets_at}. This prints a short
status line and, when the numbers change (or every 15 minutes), pushes them to your
secret gist, which the watch face reads. The push runs detached so the status line stays fast.

The gist id comes from ~/.claude-usage/config.json, written by install.py.
"""
import json
import os
import subprocess
import sys
import time

DIR = os.path.join(os.path.expanduser("~"), ".claude-usage")
CONFIG = os.path.join(DIR, "config.json")
STATE = os.path.join(DIR, "usage.json")
PUSHED = os.path.join(DIR, "pushed.json")
MIN_PUSH_GAP = 120          # seconds between gist updates when numbers change
HEARTBEAT = 15 * 60         # push even if unchanged, so the watch knows it's fresh


def push(gist_id, payload):
    body = json.dumps({"files": {"usage.json": {"content": json.dumps(payload)}}})
    flags = 0
    if os.name == "nt":
        flags = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW
    p = subprocess.Popen(["gh", "api", "-X", "PATCH", f"gists/{gist_id}", "--input", "-"],
                         stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         creationflags=flags)
    p.stdin.write(body.encode())
    p.stdin.close()


def main():
    # Windows Python defaults to the console code page; Claude Code reads UTF-8.
    sys.stdout.reconfigure(encoding="utf-8")
    try:
        data = json.load(sys.stdin)
    except ValueError:
        data = {}
    rl = data.get("rate_limits") or {}
    five = rl.get("five_hour") or {}
    week = rl.get("seven_day") or {}
    s, w = five.get("used_percentage"), week.get("used_percentage")

    parts = []
    if s is not None:
        parts.append(f"session {round(s)}%")
    if w is not None:
        parts.append(f"week {round(w)}%")
    print(" · ".join(parts))

    if s is None and w is None:
        return
    try:
        with open(CONFIG) as f:
            gist_id = json.load(f)["gist_id"]
    except (OSError, ValueError, KeyError):
        return
    now = int(time.time())
    payload = {"five_hour": s, "seven_day": w,
               "five_reset": five.get("resets_at"), "seven_reset": week.get("resets_at"),
               "updated": now}
    os.makedirs(DIR, exist_ok=True)
    with open(STATE, "w") as f:
        json.dump(payload, f)

    try:
        with open(PUSHED) as f:
            last = json.load(f)
    except (OSError, ValueError):
        last = {}
    same = all(last.get(k) == payload[k] for k in ("five_hour", "seven_day", "five_reset", "seven_reset"))
    age = now - last.get("updated", 0)
    if (not same and age >= MIN_PUSH_GAP) or age >= HEARTBEAT:
        push(gist_id, payload)
        with open(PUSHED, "w") as f:
            json.dump(payload, f)


if __name__ == "__main__":
    main()
