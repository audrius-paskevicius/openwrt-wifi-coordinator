#!/usr/bin/env python3
"""Prepend the canonical disclaimer to a release body, without duplicating it."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parent.parent
start = '<!-- project-disclaimer:start -->'
end = '<!-- project-disclaimer:end -->'


def notice():
    parts = (root / 'DISCLAIMER.txt').read_text(encoding='utf-8').strip().split('\n\n')
    return start + '\n> [!WARNING]\n> **' + parts[0] + '**\n>\n' + '\n>\n'.join('> ' + p for p in parts[1:]) + '\n' + end


def compose(body):
    if start in body and end in body:
        before, rest = body.split(start, 1)
        body = before + rest.split(end, 1)[1]
    return notice() + '\n\n' + body.lstrip()


if __name__ == '__main__':
    body = Path(sys.argv[1]).read_text(encoding='utf-8-sig')
    Path(sys.argv[2]).write_bytes(compose(body).encode('utf-8'))
