#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""phone-doctor —— 新手机接入体检（给人看的版本）

设计原则（用户思维，不是程序思维）：
  · 每一项 = 一行「人话标题 + 一句话现状 + 灯色」
  · 灯色只有四种：✅通过 / ⚠️建议处理 / ⛔必须处理 / ℹ️说明（与自动化无关，可忽略）
  · 不通过的项 **直接写"怎么修"**（编号步骤，能照做；命令给全）
  · 原始技术值塞进「技术细节」，不占主视线

用法：
  phone-doctor              体检所有终端（彩色分组输出）
  phone-doctor <serial>     只体检一台
  phone-doctor -v           连"通过/说明"的项也逐条展开
  phone-doctor --json       机器可读（手机墙/agent 用）
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import time

ADB = ["adb"]
HUB = os.environ.get("PHONE_HUB_BASE", "http://127.0.0.1:8901")
JAR = "/opt/phone-use-jar/pu.jar"
JAR_DEVICE = "/data/local/tmp/pu.jar"

C = {"ok": "\033[32m", "warn": "\033[33m", "fail": "\033[31m", "info": "\033[90m",
     "b": "\033[1m", "d": "\033[2m", "0": "\033[0m"}
ICON = {"ok": "✅", "warn": "⚠️", "fail": "⛔", "info": "ℹ️"}
LABEL = {"ok": "通过", "warn": "建议处理", "fail": "必须处理", "info": "说明"}


def sh(cmd, timeout=60, binary=False):
    try:
        p = subprocess.run(cmd, capture_output=True, timeout=timeout, stdin=subprocess.DEVNULL)
        return p.returncode, (p.stdout if binary else p.stdout.decode(errors="ignore")), p.stderr.decode(errors="ignore")
    except subprocess.TimeoutExpired:
        return 124, b"" if binary else "", "超时"


def adb(serial, *args, timeout=60, binary=False):
    return sh(ADB + ["-s", serial] + list(args), timeout=timeout, binary=binary)


def prop(serial, name):
    return adb(serial, "shell", "getprop", name)[1].strip()


def setting(serial, ns, key):
    return adb(serial, "shell", "settings", "get", ns, key)[1].strip()


def mk(cid, title, status, detail, steps=None, tech=None):
    """一条检查：标题说人话、detail 一句话现状、steps 是怎么修、tech 是原始值"""
    return {"id": cid, "title": title, "name": title, "status": status,
            "detail": detail, "steps": steps or [], "fix": " ".join(steps or []), "tech": tech}


# ---------------- 各项检查 ----------------

def check_adb_state(serial, state, raw):
    if state == "device":
        return mk("adb_state", "电脑能认出这台手机", "ok", "已授权，可以用了", tech=raw)
    if state == "unauthorized":
        return mk("adb_state", "电脑能认出这台手机", "fail",
                  "电脑看到手机了，但手机还没「允许这台电脑调试」",
                  ["看手机屏幕，弹出「允许 USB 调试吗？」→ 勾选「一律允许」→ 点「允许」",
                   "如果没弹窗：手机上 设置 → 更多设置 → 开发者选项 → 点「撤销 USB 调试授权」，然后重新插线",
                   "还是不行：换一个 USB 口（直插主机，不要用扩展坞），再插一次"], tech=raw)
    if state == "offline":
        return mk("adb_state", "电脑能认出这台手机", "fail",
                  "手机处于 offline 状态（一般是线/口/连接模式的问题）",
                  ["重新插拔数据线；换一个 USB 口直插主机（不要经扩展坞/延长线）",
                   "手机上把 USB 用途改成「传输文件(MTP)」",
                   "电脑上执行：adb kill-server && adb devices"], tech=raw)
    return mk("adb_state", "电脑能认出这台手机", "fail", "电脑没有识别到这台手机（状态：%s）" % state,
              ["换一根**能传数据**的线（很多线只能充电）",
               "换 USB 口并直插主机；手机上确认 USB 用途为「传输文件」",
               "电脑上执行：adb kill-server && adb devices"], tech=raw)


def check_dev_options(serial):
    v = setting(serial, "global", "development_settings_enabled")
    if v == "1":
        return mk("dev_options", "开发者选项已打开", "ok", "已打开", tech="development_settings_enabled=1")
    return mk("dev_options", "开发者选项已打开", "fail", "还没打开开发者选项，后面几步都做不了",
              ["手机上：设置 → 我的设备 → 全部参数 → 连点「MIUI 版本」7 次",
               "回到 设置 → 更多设置 → 开发者选项（这时才会出现）"], tech="development_settings_enabled=%s" % (v or "空"))


def check_usb_debug(serial):
    v = setting(serial, "global", "adb_enabled")
    if v == "1":
        return mk("usb_debug", "USB 调试已打开", "ok", "已打开", tech="adb_enabled=1")
    return mk("usb_debug", "USB 调试已打开", "fail", "USB 调试没开，电脑发不了任何指令",
              ["手机上：设置 → 更多设置 → 开发者选项 → 打开「USB 调试」",
               "建议顺手打开同页的「USB 调试(安全设置)」和「通过 USB 安装」",
               "打开后重新插一次线，并在手机上点「允许」"], tech="adb_enabled=%s" % (v or "空"))


def check_usb_mode(serial):
    cfg = prop(serial, "sys.usb.config")
    if "mtp" in cfg and "adb" in cfg:
        return mk("usb_mode", "USB 用途是「传输文件」", "ok", "已选传输文件，传文件/装应用都没问题", tech="sys.usb.config=%s" % cfg)
    if "adb" in cfg:
        return mk("usb_mode", "USB 用途是「传输文件」", "warn", "现在是「仅充电+调试」，传文件/装应用会失败",
                  ["手机下拉通知栏 → 点「USB 用途」→ 选「传输文件(MTP)」"], tech="sys.usb.config=%s" % cfg)
    return mk("usb_mode", "USB 用途是「传输文件」", "warn", "USB 用途没设成传输文件",
              ["手机下拉通知栏 → 点「USB 用途」→ 选「传输文件(MTP)」"], tech="sys.usb.config=%s" % (cfg or "空"))


def check_cable(serial):
    local = "/tmp/.phone_doctor_push"
    with open(local, "wb") as f:
        f.write(os.urandom(65536))
    want = hashlib.sha1(open(local, "rb").read()).hexdigest()
    t0 = time.time()
    rc, o, e = adb(serial, "push", local, "/sdcard/.phone_doctor_push", timeout=120)
    dt = max(time.time() - t0, 0.01)
    if rc != 0:
        return mk("cable", "数据线能正常传文件", "fail",
                  "传文件失败（常见原因：线只能充电 / 线老化 / 经扩展坞供电不足）",
                  ["换一根**支持数据传输**的线（原装线最稳）",
                   "直插主机 USB 口，不要经扩展坞/延长线",
                   "手机 USB 用途确认为「传输文件(MTP)」",
                   "再测一次：phone-doctor"], tech=(e or o).strip().splitlines()[-1:] or "")
    rc2, out, _ = adb(serial, "shell", "sha1sum /sdcard/.phone_doctor_push")
    adb(serial, "shell", "rm -f /sdcard/.phone_doctor_push")
    got = (out.split() or [""])[0]
    kbps = 64 / dt
    if got != want:
        return mk("cable", "数据线能正常传文件", "fail", "文件传过去后校验不一致（线材/接口接触不良）",
                  ["换线重试；换 USB 口再试", "仍失败就用这台手机换一根已知好用的线做对比"], tech="读回 %s" % got[:12])
    if dt < 8:
        return mk("cable", "数据线能正常传文件", "ok", "实测传了 64KB，速度 %.1f MB/s，很正常" % (kbps / 1024),
                  tech="push 64KB 用时 %.2fs（%.0f KB/s）" % (dt, kbps))
    return mk("cable", "数据线能正常传文件", "warn", "能传但很慢（%.0f KB/s），长任务容易超时" % kbps,
              ["换线/换口（慢线会让截图、下发注入包超时）", "确认 USB 口是 USB 2.0 以上、没经扩展坞"],
              tech="push 64KB 用时 %.2fs（%.0f KB/s）" % (dt, kbps))


def check_storage(serial):
    rc, o, _ = adb(serial, "shell", "df -h /sdcard | tail -1")
    m = re.search(r"(\d+)%", o)
    pct = int(m.group(1)) if m else None
    if pct is None:
        return mk("storage", "手机存储够用", "warn", "读不到存储占用，确认没满/没锁", tech=o.strip()[:80])
    if pct < 90:
        return mk("storage", "手机存储够用", "ok", "已用 %d%%" % pct, tech="df /sdcard")
    return mk("storage", "手机存储够用", "warn", "已用 %d%%，快满了（截图/日志会写不进去）" % pct,
              ["手机上清理空间（相册/下载/其它应用缓存）", "或删掉旧截图：adb -s %s shell rm -f /sdcard/*.png" % serial])


def check_root(serial):
    rc, o, e = adb(serial, "shell", "su", "-c", "id")
    if o.strip().startswith("uid=0"):
        return mk("root", "有 root（能力最全）", "ok", "可以点坐标、按按键、改系统配置", tech=o.strip()[:60])
    return mk("root", "有没有 root", "info",
              "没有 root —— 不影响使用：本机走「无障碍点击」，同样能点/输/滚/截图/发网络请求",
              tech=(e.strip()[:60] or "su 不存在"))


def check_input_inject(serial, root, have_alt=True):
    rc, o, e = adb(serial, "shell", "input", "tap", "1", "1")
    msg = (o + e).strip()
    plain_ok = rc == 0 and "INJECT_EVENTS" not in msg and "Injecting to another" not in msg
    if plain_ok:
        return mk("input_inject", "能按坐标点屏幕", "ok", "这台允许电脑直接点（坐标手势可用）", tech=msg[:80])
    if root:
        rc2, o2, e2 = adb(serial, "shell", "su", "-c", "input tap 1 1")
        if rc2 == 0:
            return mk("input_inject", "能按坐标点屏幕", "ok", "有 root，可以按坐标点（含手势/按键）", tech="su input tap 返回 0")
    if have_alt:
        return mk("input_inject", "能不能按坐标点屏幕", "info",
                  "这台不允许电脑按坐标点 —— 不用管，会自动改用「无障碍点击」（找到控件再点，效果一样）",
                  ["不需要处理。想更保险的话：开发者选项里打开「USB 调试(安全设置)」后重测"], tech=(msg.splitlines()[0][:90] if msg else "无输出"))
    return mk("input_inject", "能按坐标点屏幕", "fail",
              "这台不允许电脑按坐标点，而且**没有替代方案**（既无 root、无障碍点击后端也没就绪）",
              ["先修好「无障碍点击后端就绪」这一项（免 root 方案靠它）",
               "或刷 Magisk 获得 root（root 后可按坐标点）",
               "或在开发者选项里打开「USB 调试(安全设置)」后重测"], tech=(msg.splitlines()[0][:90] if msg else "无输出"))


def check_jar(serial):
    if not os.path.exists(JAR):
        return mk("jar", "无障碍点击后端就绪", "fail", "服务器上缺少注入包 pu.jar（免 root 点击靠它）",
                  ["在工作区执行 build-pu-jar.sh 重新生成", "拷贝到 /opt/phone-use-jar/pu.jar 后重测"])
    t0 = time.time()
    adb(serial, "push", JAR, JAR_DEVICE, timeout=120)
    rc, o, e = adb(serial, "shell",
                   "uiautomator runtest %s -c com.dsh.phoneuse.PhoneUseTest#testRun" % JAR_DEVICE,
                   timeout=180)
    out = o + e
    if "OK (1 test)" in out or "Tests run" in out:
        return mk("jar", "无障碍点击后端就绪", "ok", "正常（这台能点、能输入、能滚动、能截图）",
                  tech="runtest 用时 %.0fs" % (time.time() - t0))
    if "Didn't find class" in out:
        return mk("jar", "无障碍点击后端就绪", "fail", "注入包格式不对（手机加载不了）",
                  ["按 build-pu-jar.sh 重新构建（classes.dex 必须用 zip -0 压缩存储）", "重新下发后重测"],
                  tech=out.strip().splitlines()[-1][:100])
    return mk("jar", "无障碍点击后端就绪", "warn", "第一次跑失败（首次运行偶发慢/占用）",
              ["再测一次：phone-doctor %s" % serial, "仍失败：adb -s %s shell uiautomator runtest %s -c com.dsh.phoneuse.PhoneUseTest#testRun 手工看报错" % (serial, JAR_DEVICE)],
              tech=(out.strip().splitlines()[-1][:100] if out.strip() else "无输出"))


def check_install_capability(serial):
    rc, o, e = adb(serial, "shell", "pm install-create -r -t")
    out = (o + e)
    if "created install session" in out:
        return mk("install", "能用电脑安装 App", "ok", "可以（需要装自建应用时没问题）", tech=out.strip()[:60])
    if "USER_RESTRICTED" in out or "not allowed" in out.lower():
        return mk("install", "能用电脑安装 App", "warn", "系统不允许电脑直接装 App（小米常见限制）",
                  ["开发者选项里打开「通过 USB 安装」和「USB 调试(安全设置)」",
                   "或：把 APK 推到 /sdcard/Download，手机上文件管理里手动点安装（会弹确认）"], tech=out.strip()[:80])
    return mk("install", "能用电脑安装 App", "warn", "安装需要手机端确认",
              ["装的时候看手机屏幕点「允许」；被拒就改走 /sdcard/Download 手动安装"], tech=out.strip()[:80])


def check_unknown_sources(serial):
    v = setting(serial, "secure", "install_non_market_apps")
    if v == "1":
        return mk("unknown_sources", "允许安装未知来源应用", "ok", "已允许", tech="install_non_market_apps=1")
    return mk("unknown_sources", "允许安装未知来源应用", "warn", "不允许（装自建 App 时会被拦）",
              ["设置 → 隐私保护 → 特殊权限 → 安装未知应用 → 允许对应来源"], tech="install_non_market_apps=%s" % (v or "空"))


def check_screen(serial):
    rc, o, _ = adb(serial, "shell", "dumpsys power")
    wake = (re.search(r"mWakefulness=(\w+)", o) or [None, "?"])[1]
    rc2, o2, _ = adb(serial, "shell", "dumpsys window | grep -m1 mDreamingLockscreen")
    locked = "mDreamingLockscreen=true" in o2 or "mShowingLockscreen=true" in o2
    if wake == "Awake" and not locked:
        return mk("screen", "屏幕亮着、没锁屏", "ok", "正常（能直接点击操作）", tech="mWakefulness=Awake")
    return mk("screen", "屏幕亮着、没锁屏", "warn", "屏幕%s%s，点击可能不生效" % (
        "已休眠" if wake != "Awake" else "亮着", "且锁屏" if locked else ""),
        ["电脑上执行：adb -s %s shell input keyevent 224 && adb -s %s shell wm dismiss-keyguard" % (serial, serial),
         "手机上：开发者选项 → 打开「不锁定屏幕」"], tech="mWakefulness=%s locked=%s" % (wake, locked))


def check_stay_awake(serial):
    v = setting(serial, "global", "stay_on_while_plugged_in")
    if v and v != "0":
        return mk("stay_awake", "插电时屏幕不休眠", "ok", "已设置（长任务不会中途黑屏）", tech="stay_on_while_plugged_in=%s" % v)
    return mk("stay_awake", "插电时屏幕不休眠", "warn", "插电后屏幕仍会休眠，跑到一半可能点不动",
              ["电脑上执行：adb -s %s shell svc power stayon true" % serial,
               "或手机上：开发者选项 → 打开「不锁定屏幕」"], tech="stay_on_while_plugged_in=%s" % (v or "空"))


def check_battery(serial):
    rc, o, _ = adb(serial, "shell", "dumpsys battery")
    m = re.search(r"level: (\d+)", o)
    lv = int(m.group(1)) if m else None
    if lv is None:
        return mk("battery", "电量充足", "warn", "读不到电量值", ["确认电池正常；必要时换一台"], tech="")
    if lv >= 30:
        return mk("battery", "电量充足", "ok", "%d%%" % lv, tech="dumpsys battery level")
    if lv >= 15:
        return mk("battery", "电量充足", "warn", "只剩 %d%%，建议插上电源" % lv,
                  ["插上充电线（低电量会降频、自动休眠，容易让用例半途失败）"], tech="level=%d" % lv)
    return mk("battery", "电量充足", "fail", "只有 %d%%（会休眠/降频，跑不了长任务）" % lv,
              ["立刻插上充电线，等电量 >30% 再跑用例"], tech="level=%d" % lv)


def check_time_sync(serial):
    rc, o, _ = adb(serial, "shell", "date +%s")
    try:
        ph = int(o.strip())
    except Exception:
        return mk("time_sync", "手机时间与服务器一致", "warn", "读不到手机时间",
                  ["手机上：设置 → 日期与时间 → 打开「自动设置」"], tech="")
    skew = abs(ph - int(time.time()))
    if skew <= 30:
        return mk("time_sync", "手机时间与服务器一致", "ok", "相差 %.0f 秒" % skew, tech="%d vs %d" % (ph, int(time.time())))
    return mk("time_sync", "手机时间与服务器一致", "fail", "相差 %.0f 秒（时间不对会让 1X/门户认证莫名失败）" % skew,
              ["手机上：设置 → 日期与时间 → 打开「自动设置」",
               "有 root 也可：adb -s %s shell su -c 'date -s @%d'" % (serial, int(time.time()))], tech="skew=%.0fs" % skew)


def check_wifi_cmd(serial, android):
    """真测一次：用一个临时 SSID 调 connect-network，测完立刻删掉（不留垃圾）
    判定口径（用户要求：完全无人值守）——**不能自动连网 = 这台不可用**"""
    rc, o, _ = adb(serial, "shell", "cmd wifi help")
    if "connect-network" not in o:
        return mk("wifi_cmd", "能自动连网（无人值守必需）", "fail",
                  "这台系统（Android %s）没有「电脑直接连网」的命令 → 派任务后没人能替它连上 WiFi" % android,
                  ["给这台 root（root 后 `su -c cmd wifi connect-network` 可用）",
                   "或换一台能自动连网的机器（如 MIUI14/Android 12 那类已验证机型）",
                   "这台只能人工连网后再用 —— 不符合无人值守要求，按「不可用」处理"],
                  tech="cmd wifi connect-network 不存在")
    probe_ssid = "phone-doctor-probe"
    rc, o, e = adb(serial, "shell", "cmd", "wifi", "connect-network", probe_ssid, "open", timeout=40)
    out = (o + e)
    ok = "Connection initiated" in out
    # 清理：把刚才建的临时配置删掉（必须，不留垃圾）
    rc2, nets, _ = adb(serial, "shell", "cmd", "wifi", "list-networks")
    for line in nets.splitlines():
        if probe_ssid in line:
            m = re.match(r"\s*(\d+)", line)
            if m:
                adb(serial, "shell", "cmd", "wifi", "forget-network", m.group(1))
    if ok:
        return mk("wifi_cmd", "能自动连网（无人值守必需）", "ok",
                  "可以（电脑能命令它连网，还支持锁 BSSID / 指定 MAC）",
                  tech="实测 cmd wifi connect-network 返回 Connection initiated（临时配置已清理）")
    return mk("wifi_cmd", "能自动连网（无人值守必需）", "fail",
              "系统**不允许电脑命令它连网**（命令被权限拒绝）→ 无人值守跑不了",
              ["给这台 root（root 后 su 有权限执行该命令）",
               "或换一台能自动连网的机器",
               "这台只能人工连网后再用 —— 不符合无人值守要求，按「不可用」处理"],
              tech=(out.strip().splitlines()[-1][:120] if out.strip() else "无输出"))


def check_captive_login(serial):
    rc, o, _ = adb(serial, "shell", "pm list packages com.android.captiveportallogin")
    if "captiveportallogin" in o:
        return mk("captive_login", "有系统门户登录页（做 portal 认证要用）", "ok", "具备，可以直接走门户认证流程", tech="captiveportallogin 存在")
    return mk("captive_login", "有系统门户登录页（做 portal 认证要用）", "warn",
              "系统精简掉了门户登录页（做 portal 认证要换办法）",
              ["改用浏览器打开门户地址：adb -s %s shell am start -a android.intent.action.VIEW -d <门户URL>" % serial,
               "或点 WLAN 列表里该网络的「登录到网络」触发厂商门户 App"], tech="未找到 captiveportallogin")


def check_accessibility(serial):
    enabled = setting(serial, "secure", "accessibility_enabled")
    svcs = setting(serial, "secure", "enabled_accessibility_services")
    n = len([x for x in (svcs or "").split(":") if x])
    if enabled == "1" and n:
        return mk("accessibility", "无障碍服务（本方案不需要）", "info", "当前开着 %d 个服务" % n,
                  tech="accessibility_enabled=1, %d 个服务" % n)
    return mk("accessibility", "无障碍服务（本方案不需要）", "info",
              "没开 —— 与本方案无关，不用管（我们走的是 UiAutomation，不依赖它）",
              ["只有用 Portal / MobileAgent 这类「装 App」的方案时才需要：设置 → 更多设置 → 无障碍 → 已下载的服务 → 打开",
               "MIUI 会把无障碍服务自动关掉，发现失效就重新打开"],
              tech="accessibility_enabled=%s services=%s" % (enabled or "空", (svcs or "空")[:40]))


def check_miui_limits(serial):
    mi = prop(serial, "ro.miui.ui.version.name")
    if not mi:
        return None
    return mk("miui_limits", "小米系统已知限制（了解即可）", "info",
              "有 4 条已知限制，本方案已自动绕开，不用处理",
              ["中文名字的 WiFi 不显示在系统列表里 → 用电脑命令直连（本方案已用）",
               "设置里的下拉框点不动 → 改从扫描列表里点网络名（本方案已用）",
               "系统可能不允许按坐标点屏 → 走无障碍点击（本方案已用）",
               "App 的无障碍服务会被系统自动关 → 只有用 App 方案时才需要关注"],
              tech="MIUI %s" % mi)


def check_lease(serial):
    try:
        import urllib.request
        with urllib.request.urlopen(HUB + "/devices/%s" % serial, timeout=10) as r:
            d = json.loads(r.read().decode())
        if d.get("state") == "busy":
            l = d.get("lease") or {}
            return mk("lease", "没被别人占用", "warn",
                      "正被 %s 使用（还剩 %s 秒）" % (l.get("owner"), l.get("remaining_s")),
                      ["等它用完再派任务（会自动排队）", "确认对方是卡死任务才用：phone-hub reclaim %s" % serial],
                      tech=json.dumps(l, ensure_ascii=False)[:120])
        return mk("lease", "没被别人占用", "ok", "空闲", tech="idle")
    except Exception as e:
        return mk("lease", "没被别人占用", "warn", "查不到占用状态（hub 没响应？）",
                  ["确认服务在跑：systemctl status phone-hub"], tech=str(e))


# ---------------- 主流程 ----------------

def device_states():
    rc, o, _ = sh(ADB + ["devices", "-l"])
    out = []
    for line in o.splitlines()[1:]:
        p = line.split()
        if len(p) >= 2:
            out.append((p[0], p[1], line.strip()))
    return out


def doctor(serial, state, raw):
    checks = [check_adb_state(serial, state, raw)]
    if state == "device":
        android = prop(serial, "ro.build.version.release")
        model = prop(serial, "ro.product.model")
        root = adb(serial, "shell", "su", "-c", "id")[1].strip().startswith("uid=0")
        jar = check_jar(serial)                      # 先跑（后面判断"有没有替代方案"要用）
        checks += [check_dev_options(serial), check_usb_debug(serial), check_usb_mode(serial),
                   check_cable(serial), check_storage(serial), check_root(serial),
                   check_input_inject(serial, root, have_alt=(root or jar["status"] == "ok")), jar]
        checks += [check_install_capability(serial), check_unknown_sources(serial)]
        checks += [check_screen(serial), check_stay_awake(serial), check_battery(serial),
                   check_time_sync(serial)]
        checks += [check_wifi_cmd(serial, android), check_captive_login(serial),
                   check_accessibility(serial)]
        mi = check_miui_limits(serial)
        if mi:
            checks.append(mi)
        checks.append(check_lease(serial))
        inp = next((c for c in checks if c["id"] == "input_inject"), None)
        backend = "root-input" if root else (
            "input" if inp and inp["status"] == "ok" else "jar-node-action")
    else:
        model = android = None
        root = False
        backend = None
    fails = [c for c in checks if c["status"] == "fail"]
    warns = [c for c in checks if c["status"] == "warn"]
    jar_ok = any(c["id"] == "jar" and c["status"] == "ok" for c in checks)
    wifi_ok = any(c["id"] == "wifi_cmd" and c["status"] == "ok" for c in checks)
    # 判定口径：无人值守 = 动作后端可用 **且** 能自动连网（用户要求：不能自动连网 → 不可用）
    ready = (not fails) and wifi_ok and (jar_ok or root or backend == "input") and state == "device"
    # —— 能力摘要：说清"这台能做什么、不能做什么"（避免"✅可以用"和"不能连网"看起来自相矛盾）——
    can, cannot = [], []
    if jar_ok:
        can += ["看界面/点按钮/输入文字/滚动/截图", "读网络状态、发 HTTP 探测",
                "1X(802.1X) 认证（走设置界面配置）", "portal 门户认证（驱动门户网页填账号密码）"]
    if root:
        can += ["按坐标点屏/手势/按键（root）", "改系统配置"]
    wcmd = next((c for c in checks if c["id"] == "wifi_cmd"), None)
    if wcmd and wcmd["status"] == "ok":
        can += ["用一条命令连开放/PSK 的 WiFi（可锁 BSSID、指定 MAC）"]
    else:
        cannot += ["自动连网（没有权限执行连网命令）→ 不符合无人值守要求"]
    if not any(c["id"] == "captive_login" and c["status"] == "ok" for c in checks):
        cannot += ["用系统门户登录页做 portal 认证（系统精简了，需改用浏览器打开门户）"]
    if state != "device":
        can, cannot = [], ["这台现在连不上（先解决第一项）"]

    if state != "device":
        verdict = "不可用 —— 先解决「电脑能认出这台手机」这一项"
    elif fails:
        verdict = "不可用 —— 先处理下面「必须处理」的 %d 项" % len(fails)
    else:
        verdict = "可用 —— 无人值守所需的能力都具备，直接派任务就行"
    return {"serial": serial, "model": model, "android": android, "root": root, "backend": backend,
            "state": state, "ready": ready, "verdict": verdict, "can": can, "cannot": cannot,
            "checks": checks, "blockers": [c["title"] for c in fails],
            "warnings": [c["title"] for c in warns],
            "counts": {"ok": sum(1 for c in checks if c["status"] == "ok"),
                       "warn": len(warns), "fail": len(fails),
                       "info": sum(1 for c in checks if c["status"] == "info")},
            "checked_at": time.time()}


def human(rep, verbose=False):
    c = C
    print("\n" + c["b"] + "━" * 78 + c["0"])
    head = "%s · %s · Android %s%s" % (rep["serial"], rep.get("model") or "?",
                                       rep.get("android") or "?", " · 有 root" if rep["root"] else "")
    print(" " + c["b"] + head + c["0"])
    mark = c["ok"] + "✅" if rep["ready"] else c["fail"] + "⛔"
    print(" " + mark + " " + c["b"] + rep["verdict"] + c["0"])
    n = rep["counts"]
    print(" " + c["d"] + "通过 %d · 建议处理 %d · 必须处理 %d · 说明 %d" % (
        n["ok"], n["warn"], n["fail"], n["info"]) + c["0"])
    print(c["b"] + "━" * 78 + c["0"])
    if rep.get("can"):
        print(" " + c["ok"] + "这台能做：" + c["0"] + "；".join(rep["can"]))
    if rep.get("cannot"):
        print(" " + c["warn"] + "做不到：" + c["0"] + "；".join(rep["cannot"]))

    for status, title in (("fail", "⛔ 必须处理"), ("warn", "⚠️ 建议处理")):
        items = [x for x in rep["checks"] if x["status"] == status]
        print("\n%s%s（%d）%s" % (c[status], title, len(items), c["0"]))
        if not items:
            print("  " + c["d"] + "无" + c["0"])
            continue
        for i, x in enumerate(items, 1):
            print(" %d. %s%s%s" % (i, c["b"], x["title"], c["0"]))
            print("    现在：%s" % x["detail"])
            if x["steps"]:
                print("    怎么修：")
                for j, s in enumerate(x["steps"], 1):
                    print("      %d) %s" % (j, s))
            if x.get("tech"):
                print("    " + c["d"] + "技术细节：" + str(x["tech"])[:110] + c["0"])

    for status, title in (("ok", "✅ 通过"), ("info", "ℹ️ 说明")):
        items = [x for x in rep["checks"] if x["status"] == status]
        print("\n%s%s（%d）%s%s" % (c[status], title, len(items), c["0"],
                                  "" if verbose else c["d"] + "  —— 加 -v 展开" + c["0"]))
        if verbose:
            for x in items:
                print("   %s %-34s %s" % (ICON[status], x["title"], x["detail"]))


def main():
    a = sys.argv[1:]
    as_json = "--json" in a
    verbose = "-v" in a or "--verbose" in a
    a = [x for x in a if x not in ("--json", "-v", "--verbose")]
    want = a[0] if a else None
    reps = []
    for serial, state, raw in device_states():
        if want and serial != want:
            continue
        reps.append(doctor(serial, state, raw))
    if not reps:
        msg = ("没有检测到任何手机。请检查：" 
               "① 数据线是不是只能充电的线（换一根能传数据的）；"
               "② 手机是否已开「USB 调试」并在弹窗里点了「允许」；"
               "③ 换一个 USB 口直插主机后重试。")
        if as_json:
            print(json.dumps({"error": "no device", "hint": msg}, ensure_ascii=False))
        else:
            print("\n⛔ " + msg)
        return 1
    if as_json:
        print(json.dumps({"devices": reps, "ready": sum(1 for r in reps if r["ready"])}, ensure_ascii=False))
    else:
        for r in reps:
            human(r, verbose)
        good = sum(1 for r in reps if r["ready"])
        print("\n" + C["b"] + "结论：%d/%d 台可以用%s" % (good, len(reps), C["0"]))
    return 0 if all(r["ready"] for r in reps) else 2


if __name__ == "__main__":
    sys.exit(main())
