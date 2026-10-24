"""Sets up the Claude usage feed for the Holo Terminal watch face.

  python install.py            create a secret gist, install the status line script, print what to add
  python install.py --apply    same, and also add the statusLine entry to ~/.claude/settings.json
                               (a backup is written next to it first)

Needs the GitHub CLI (gh) signed in with the "gist" scope, and a Claude Pro or Max plan:
Claude Code only reports plan usage to the status line for those plans.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HOME = os.path.expanduser("~")
DIR = os.path.join(HOME, ".claude-usage")
CONFIG = os.path.join(DIR, "config.json")
SCRIPT = os.path.join(DIR, "statusline.py")
SETTINGS = os.path.join(HOME, ".claude", "settings.json")


def gh(*args, stdin=None):
    return subprocess.run(["gh", *args], input=stdin, capture_output=True, text=True, check=True).stdout


def main():
    apply = "--apply" in sys.argv
    if shutil.which("gh") is None:
        sys.exit("The GitHub CLI (gh) isn't installed: https://cli.github.com")
    try:
        gh("auth", "status")
    except subprocess.CalledProcessError:
        sys.exit("Sign in first: gh auth login --scopes gist")

    os.makedirs(DIR, exist_ok=True)
    if os.path.exists(CONFIG):
        gist_id = json.load(open(CONFIG))["gist_id"]
        print(f"Using your existing gist {gist_id}")
    else:
        seed = {"five_hour": None, "seven_day": None, "five_reset": None, "seven_reset": None,
                "updated": int(time.time())}
        tmp = os.path.join(tempfile.mkdtemp(), "usage.json")
        with open(tmp, "w") as f:
            json.dump(seed, f)
        url = gh("gist", "create", tmp, "--desc", "Claude usage for the Holo Terminal watch face").strip().splitlines()[-1]
        gist_id = url.rstrip("/").split("/")[-1]
        with open(CONFIG, "w") as f:
            json.dump({"gist_id": gist_id}, f)
        print(f"Created secret gist {url}")

    shutil.copy(os.path.join(os.path.dirname(os.path.abspath(__file__)), "statusline.py"), SCRIPT)
    user = gh("api", "user", "--jq", ".login").strip()
    raw = f"https://gist.githubusercontent.com/{user}/{gist_id}/raw/usage.json"
    command = f'"{sys.executable}" "{SCRIPT}"'.replace("\\", "/")
    entry = {"type": "command", "command": command}

    if apply:
        settings = {}
        if os.path.exists(SETTINGS):
            shutil.copy(SETTINGS, SETTINGS + ".bak")
            with open(SETTINGS, encoding="utf-8") as f:
                settings = json.load(f)
        if "statusLine" in settings and settings["statusLine"] != entry:
            print("Replacing your existing statusLine (backup in settings.json.bak):")
            print("  " + json.dumps(settings["statusLine"]))
        settings["statusLine"] = entry
        os.makedirs(os.path.dirname(SETTINGS), exist_ok=True)
        with open(SETTINGS, "w", encoding="utf-8") as f:
            json.dump(settings, f, indent=2)
        print(f"Added the status line to {SETTINGS}")
    else:
        print("\nAdd this to ~/.claude/settings.json (or rerun with --apply):")
        print(json.dumps({"statusLine": entry}, indent=2))

    print("\nIn the watch face's settings (Garmin Connect app > Connect IQ > Holo Terminal), set")
    print(f"  Claude usage URL = {raw}")
    print("\nThe numbers update while a Claude Code session is running.")


if __name__ == "__main__":
    main()
