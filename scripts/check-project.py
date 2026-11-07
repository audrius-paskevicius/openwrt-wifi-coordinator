#!/usr/bin/env python3
"""Portable source/release checks. No authentication or router access required."""
import hashlib
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
errors = []
ignored = {".git", "__pycache__", "dist"}
private_key = re.compile(r"-----BEGIN (?:[A-Z]+ )?" + r"PRIVATE KEY-----")
token = re.compile(r"\b(?:gh[pousr]_" + r"[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})\b")
personal = re.compile(r"C:[/\\]" + r"Users[/\\]")
required = ["README.md", "LICENSE", "VERSION", "wifi-coordinator/build-apk.sh",
            "channel-coordinator/files/main.uc", "radio-prefer/files/main.uc",
            "radio-prefer/release/radio-prefer-public.pem", "release/SHA256SUMS"]
for name in required:
    if not (root / name).is_file():
        errors.append("Missing required file: " + name)

count = 0
for path in root.rglob("*"):
    if not path.is_file() or any(part in ignored for part in path.relative_to(root).parts):
        continue
    if path.suffix in (".apk", ".adb", ".zip", ".png", ".pyc"):
        continue
    relative = str(path.relative_to(root))
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeError:
        errors.append("Unexpected non-UTF8 file: " + relative)
        continue
    count += 1
    for pattern, label in [(private_key, "private key"), (token, "credential token"),
                           (personal, "local machine reference")]:
        if pattern.search(text):
            errors.append("Possible " + label + " in " + relative)
    if path.suffix == ".pem" and not text.startswith("-----BEGIN PUBLIC KEY-----"):
        errors.append("PEM file is not a public key: " + relative)
    if path.suffix == ".json":
        try:
            json.loads(text)
        except ValueError:
            errors.append("Invalid JSON: " + relative)

for line in (root / "release/SHA256SUMS").read_text(encoding="ascii").splitlines():
    expected, name = line.split(None, 1)
    name = name.strip()
    path = (root / "release" / name).resolve()
    if root not in path.parents or not path.is_file():
        errors.append("Invalid checksum path: " + name)
    elif hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        errors.append("Checksum mismatch: " + name)

if errors:
    raise SystemExit("\n".join(errors))
print("PASS: {} text files, required source, JSON, release checksums and credential patterns".format(count))
