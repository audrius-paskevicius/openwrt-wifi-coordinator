#!/usr/bin/env python3
"""Portable source/release checks. No authentication or router access required."""
import json
import re
from pathlib import Path
from urllib.parse import unquote, urlsplit

root = Path(__file__).resolve().parent.parent
errors = []
ignored = {".git", "__pycache__", "dist"}
private_key = re.compile(r"-----BEGIN (?:[A-Z]+ )?" + r"PRIVATE KEY-----")
token = re.compile(r"\b(?:gh[pousr]_" + r"[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})\b")
personal = re.compile(r"C:[/\\]" + r"Users[/\\]")
required = ["README.md", "LICENSE", "VERSION", "wifi-coordinator/build-apk.sh",
            "channel-coordinator/files/main.uc", "radio-prefer/files/main.uc",
            "radio-prefer/release/radio-prefer-public.pem", "docs/ARCHITECTURE.md"]
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
    if path.suffix == ".md":
        for target in re.findall(r"\[[^\]]*\]\(([^)]+)\)", text):
            link = urlsplit(target)
            if link.scheme or link.netloc or not link.path:
                continue
            if not (path.parent / unquote(link.path)).exists():
                errors.append("Broken documentation link in {}: {}".format(relative, target))

if errors:
    raise SystemExit("\n".join(errors))
print("PASS: {} text files, required source, documentation links, JSON and credential patterns".format(count))
