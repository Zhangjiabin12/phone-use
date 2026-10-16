#!/usr/bin/env python3
"""把命令喂给 pu.jar 在手机上跑（免 root / 免装 APK）
支持 ANDROID_SERIAL 指定终端（多台时必须）。
用法: pu-node.py <<'EOF'
  ui
  click-text 我要上网
EOF
"""
import os
import subprocess
import sys
import time

CMD_LOCAL = "/tmp/pu_cmd.txt"
OUT_DEVICE = "/sdcard/pu_out.txt"
JAR = "/opt/phone-use-jar/pu.jar"
JAR_DEVICE = "/data/local/tmp/pu.jar"
SERIAL = os.environ.get("ANDROID_SERIAL") or None


def serial():
    global SERIAL
    if SERIAL:
        return SERIAL
    out = subprocess.run(["adb", "devices"], capture_output=True, text=True).stdout
    devs = [l.split()[0] for l in out.splitlines()[1:] if len(l.split()) >= 2 and l.split()[1] == "device"]
    if not devs:
        raise SystemExit("没有可用设备")
    SERIAL = devs[0]
    return SERIAL


def adb(s, *args, timeout=180):
    return subprocess.run(["adb", "-s", s, *args], capture_output=True, text=True,
                          timeout=timeout, stdin=subprocess.DEVNULL)


def main():
    raw = sys.stdin.read()
    cmds = []
    for line in raw.splitlines():
        line = line.rstrip("\r")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if "\\u" in line:
            line = line.encode("utf-8").decode("unicode_escape")
        cmds.append(line)
    if not cmds:
        raise SystemExit("没有命令")

    s = serial()
    adb(s, "push", JAR, JAR_DEVICE)
    with open(CMD_LOCAL, "w", encoding="utf-8") as f:
        f.write("\n".join(cmds) + "\n")
    print("== %d 条命令 → %s ==" % (len(cmds), s))
    for c in cmds:
        print("   " + c)
    adb(s, "push", CMD_LOCAL, "/sdcard/pu_cmd.txt")
    adb(s, "shell", "rm -f " + OUT_DEVICE)
    t0 = time.time()
    r = adb(s, "shell", "uiautomator runtest %s -c com.dsh.phoneuse.PhoneUseTest#testRun" % JAR_DEVICE,
            timeout=240)
    tail = [l for l in (r.stdout or "").splitlines() if l.strip()][-2:]
    print("== runtest（%.1fs）: %s" % (time.time() - t0, " | ".join(tail)))
    out = adb(s, "shell", "cat " + OUT_DEVICE)
    print("== 结果 ==")
    print((out.stdout or "").replace("\r", ""))


if __name__ == "__main__":
    main()
