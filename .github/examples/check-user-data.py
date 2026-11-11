#!/usr/bin/env python3
"""Static checks for the cloud-init user-data examples.

    check-user-data.py FILE...

For each file:
  - first line is exactly "#cloud-config" (cloud-init ignores the file otherwise)
  - parses as YAML to a mapping
  - every bootcmd/runcmd entry given as a string passes `sh -n`
  - every write_files entry whose path ends in .json holds valid JSON
  - every doas rule it sets up passes `doas -C`: users[].doas, write_files
    under /etc/doas*, and quoted 'permit ...' strings in runcmd/bootcmd (which
    is how the commented example once appended an invalid "nopasswd" rule)

doas -C only parses; it does not check that named users exist. Exits 1 if any
check fails. Needs PyYAML and, for the doas checks, OpenDoas's doas (the doas
Alpine ships); without doas those checks fail rather than pass silently.
"""
import json
import re
import shutil
import subprocess
import sys
import tempfile

import yaml

PERMIT_IN_SHELL = re.compile(r"""['"]((?:permit|deny)\s[^'"\n]*)['"]""")
failed = False


def report(ok, what):
    global failed
    print(f"{'ok' if ok else 'FAIL'}: {what}")
    failed |= not ok


def doas_rules(doc):
    for user in doc.get("users") or []:
        if isinstance(user, dict):
            yield from user.get("doas") or []
    for wf in doc.get("write_files") or []:
        if str(wf.get("path", "")).startswith("/etc/doas"):
            yield from str(wf.get("content", "")).splitlines()
    for key in ("bootcmd", "runcmd"):
        for cmd in doc.get(key) or []:
            if isinstance(cmd, str):
                yield from PERMIT_IN_SHELL.findall(cmd)


def check(path):
    with open(path) as f:
        text = f.read()
    report(text.split("\n", 1)[0] == "#cloud-config",
           f"{path}: first line is #cloud-config")
    try:
        doc = yaml.safe_load(text)
    except yaml.YAMLError as e:
        report(False, f"{path}: YAML: {e}")
        return
    if not isinstance(doc, dict):
        report(False, f"{path}: top level is a mapping")
        return
    report(True, f"{path}: parses as YAML")

    for key in ("bootcmd", "runcmd"):
        for i, cmd in enumerate(doc.get(key) or []):
            if not isinstance(cmd, str):
                continue  # list form is exec'd directly, not by a shell
            r = subprocess.run(["sh", "-n", "-c", cmd],
                               capture_output=True, text=True)
            first = cmd.strip().splitlines()[0][:60]
            report(r.returncode == 0,
                   f"{path}: {key}[{i}] sh -n ({first})"
                   + (f": {r.stderr.strip()}" if r.returncode else ""))

    for wf in doc.get("write_files") or []:
        p = str(wf.get("path", ""))
        if p.endswith(".json"):
            try:
                json.loads(wf.get("content", ""))
                report(True, f"{path}: write_files {p} is valid JSON")
            except ValueError as e:
                report(False, f"{path}: write_files {p}: {e}")

    rules = [r.strip() for r in doas_rules(doc)
             if r.strip() and not r.strip().startswith("#")]
    if not rules:
        return
    doas = shutil.which("doas")
    if not doas:
        report(False, f"{path}: {len(rules)} doas rule(s) found but no doas "
                      "binary to check them (install opendoas)")
        return
    with tempfile.NamedTemporaryFile("w", suffix=".conf") as tmp:
        tmp.write("\n".join(rules) + "\n")
        tmp.flush()
        r = subprocess.run([doas, "-C", tmp.name],
                           capture_output=True, text=True)
    report(r.returncode == 0,
           f"{path}: doas -C on {rules}"
           + (f": {r.stderr.strip()}" if r.returncode else ""))


if len(sys.argv) < 2:
    sys.exit(__doc__)
for p in sys.argv[1:]:
    check(p)
sys.exit(1 if failed else 0)
