#!/usr/bin/env python3
"""Prepare isolated test copies from production source; never edit router config."""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
production = root / "channel-coordinator" / "files"
tests = root / "wifi-coordinator"


def read(path):
    return path.read_text(encoding="utf-8")


def write(name, content):
    (tests / name).write_text(content.replace("\r\n", "\n"), encoding="utf-8")


history = read(production / "history.uc")
history = history.replace("/tmp/wifi-coordinator-history.json", "/tmp/wifi-history-test.json")
history = history.replace("'./history-storage.uc'", "'./history-storage-test.uc'")
history = history.replace("'./policy.uc'", "'../channel-coordinator/files/policy.uc'")
history = history.replace("time()", "NOW")
history = history.replace("const PATH=", "let NOW=time();\nexport function set_now(t){NOW=t;};\nconst PATH=")
write("history-test-module.uc", history)
storage = read(production / "history-storage.uc")
storage = storage.replace("DIRECTORY='/etc/wifi-coordinator'", "DIRECTORY='/tmp/wifi-history-test-archive'")
storage = storage.replace("system('sync')", "0")
write("history-storage-test.uc", storage)

main = read(production / "main.uc")
start = main.index("function restore_preparation()")
end = main.index("if(ARGV[0]=='--recover')", start)
write("test-reconnect-recovery.uc", read(root / "tests/recovery-header.uc") + "\n" +
      main[start:end] + "\n" + read(root / "tests/recovery-cases.uc"))
start = main.index("function sample(radios)")
end = main.index("    for(let mac,at in state.forced", start)
write("test-comparison-snapshot.uc", "import {same,group} from '../channel-coordinator/files/policy.uc';\n" +
      "let state={},executor=null;function now(){return 100;}\n" + main[start:end] + "}\n" +
      read(root / "tests/comparison-cases.uc"))
start = main.index("function candidates(r,radios,rules)")
end = main.index("function sum_overlap", start)
write("test-width-limit.uc", read(root / "tests/width-limit-header.uc") + "\n" +
      main[start:end] + "\n" + read(root / "tests/width-limit-cases.uc"))
print("Prepared isolated history, recovery, comparison and width-limit test modules.")
