# 手机接入检查清单（ONBOARD）—— 新手机插上后要做什么、踩过的坑怎么修

> 适用：往 **131.255.36.102** 的手机农场（phone-hub / phone-agent / phone-wall）里加新终端。
> 自动体检：`phone-doctor`（全项）/ `phone-doctor <serial>`（单台）/ `--json`（机器读）；
> 也可以直接 `POST /devices/<serial>/doctor`。**每项不通过都会直接给出"修法"。**

---

## 一、10 步接入流程（照着做，中间任何一步不过就查第三节）

| # | 做什么 | 命令 / 位置 | 通过标准 |
|---|---|---|---|
| 1 | **用能传数据的线插到 102** | 直插主机 USB 口（别用 hub/延长线/只充电的线） | 手机通知栏出现"正在通过 USB 传输文件" |
| 2 | **USB 用途选"传输文件(MTP)"** | 手机下拉通知栏 → 点 USB 用途 | `adb shell getprop sys.usb.config` 含 `mtp,adb` |
| 3 | **开开发者选项** | 设置→我的设备→全部参数→连点"MIUI 版本"7 次 | `settings get global development_settings_enabled` = 1 |
| 4 | **开 USB 调试**（顺带开"USB 调试(安全设置)"） | 设置→更多设置→开发者选项 | `settings get global adb_enabled` = 1 |
| 5 | **手机上点"允许 USB 调试"并勾选"一律允许"** | 插线时弹窗 | `adb devices` 里该机器的状态是 `device`（不是 `unauthorized`） |
| 6 | **确认能传文件** | `adb -s <sn> push 64KB文件 /sdcard/ && adb -s <sn> shell sha1sum /sdcard/…` | 校验一致、速度正常（几十 KB/s 以上） |
| 7 | **让它常亮 + 解锁** | `adb -s <sn> shell svc power stayon true`；`wm dismiss-keyguard` | `stay_on_while_plugged_in` ≠ 0；`mWakefulness=Awake`、未锁屏 |
| 8 | **确认动作后端** | `phone-doctor <sn>` 看 `backend`；或 hub 的 `backend` 字段 | `root-input`（有 root）/ `jar-node-action`（免 root，pu.jar 就绪）/ 都不能用 → 查第三节 |
| 9 | **（可选）装 App + 开无障碍** | 只有用 Portal / MobileAgent 这类 App 方案才需要（见下） | 无障碍服务在 `enabled_accessibility_services` 里 |
| 10 | **登记进农场并体检** | `adb devices` 能看到 → hub 自动收录；`phone-hub ls` / `phone-doctor` 复检 | `phone-hub ls` 里 `state=idle`、`jar=Y`；`usable=true` |

接入完成后，只需对 agent 说一句话即可用，例如：
```
phone-agent "连 928wpa2-psk 密码 12345678"                 # 自动挑一台
phone-agent "两台一起连 test-portal2 做 portal 认证 账号 zjb 密码 123456"   # 自己扇出
```

---

## 二、体检项一览（`phone-doctor` 会逐项给结论）

**怎么看结果（已经改成给人看的了）**：每一项只有四种灯色，结论在开头一句话说清；不通过的项**直接写"怎么修"**（编号步骤，命令给全）；原始技术值收在「技术细节」里。

| 灯色 | 含义 | 你要做什么 |
|---|---|---|
| ✅ 通过 | 这项没问题 | 不用管 |
| ⚠️ 建议处理 | 不处理也能跑，但**可能半途失败** | 照"怎么修"做一下更稳 |
| ⛔ 必须处理 | 不做就用不了 | 照"怎么修"做完再体检一次 |
| ℹ️ 说明 | 与本方案**无关**（如"无障碍服务""MIUI 已知限制"） | 忽略即可 |

手机墙上：卡片徽章一眼看状态；有硬阻塞时出现**红框「为什么用不了 + 修法」**；点「体检」出面板——
绿色总结条（「✅ 可以用 —— 直接派任务就行」+ 通过/建议/必须/说明 计数）、**黄色"建议处理"卡片**、
**红色"必须先处理"卡片**（每条含"现在是什么情况 / 怎么修（1、2、3）/ 技术细节"），以及可折叠的
「✅ 已通过」「ℹ️ 说明」两段。

> 视觉形态参照成熟做法：**flutter doctor** 的分组+修法（[flutter/flutter#2132](https://github.com/flutter/flutter/issues/2132)）、
> **GitHub Actions / Checks UI** 的状态行（[pull-panda Checks Tab](https://deepwiki.com/Artmann/pull-panda-desktop/5.3-checks-tab)）、
> **Bootstrap/Tailwind 的 alert + list-group**、**Ant Design Result/Steps 的"结论+步骤"**。样式内嵌，不依赖外网 CDN。

| 检查 | 不通过会怎样 | 关键事实 |
|---|---|---|
| `adb_state` | 手机根本不在列表 / 状态不是 device | `unauthorized` / `offline` / `no permissions` 各有修法 |
| `dev_options` | 无法开 USB 调试 | MIUI 要连点版本号 7 次 |
| `usb_debug` | adb 全部命令失败 | `adb_enabled=1` |
| `usb_mode` | 传文件/装 APK 失败 | `sys.usb.config` 要含 `mtp,adb` |
| `cable` | **能列设备但 push 失败**（我们踩过：坏线/只充电线） | 实测 push 64KB + sha1 校验 |
| `storage` | 截图/日志写不进去 | `/sdcard` 已用 <90% |
| `root` | 不能用坐标手势/改 supplicant | 无 root 不影响节点动作方案 |
| `input_inject` | **开了调试模式仍点不动**（INJECT_EVENTS 被拦） | 免 root 走节点动作；否则见第三节 ③ |
| `jar` | 免 root 下点/输/滚全废 | pu.jar + uiautomator runtest |
| `install` | 装不了 APK | `adb install` 受 MIUI 限制 → 手动装 |
| `unknown_sources` | 装自建 APK 被拦 | `install_non_market_apps=1` |
| `screen` / `stay_awake` | 跑到一半休眠→点击失败 | 常亮 + 解锁 |
| `battery` | 低电休眠/降频 | ≥30% 稳 |
| `time_sync` | **1X/门户认证莫名失败** | 与 102 相差 >30s 就会出问题 |
| `wifi_cmd` | 免 root 无法自动上线开放/PSK | Android 11+ 才有 `cmd wifi connect-network` |
| `captive_login` | 门户认证没有系统登录页 | `com.android.captiveportallogin` |
| `accessibility` | App 型方案不可用 | 本项目 pu.jar **不需要**无障碍服务 |
| `miui_limits` | 记录已知限制 | 见第三节 ① ② |
| `lease` | 别人正在用这台 | `phone-hub release <sn>` |

---

## 三、踩过的坑：现象 → 原因 → 解决

### ① 数据线不行 / 传文件失败
- **现象**：`adb devices` 能看到手机，但 `adb push` 失败或极慢；装 APK、截图取证都失败。
- **原因**：**只充电的线**（没有数据线芯）、线材老化/接口氧化、经过 USB hub 或延长线供电不足、USB 用途停在"仅充电"。
- **解决**：
  1. 换**支持数据传输**的线（原装线最稳），直插主机后面板 USB 口，不经过 hub/延长线；
  2. 手机通知栏 → USB 用途 → **传输文件(MTP)**；
  3. 复测：`phone-doctor <sn>` 的 `cable` 项会实测 push 64KB 并校验 sha1；
  4. 仍失败：换一台手机试同一根线，**区分是线的问题还是手机口的问题**。

### ② 没开调试模式 / 没授权
- **现象**：`adb devices` 里看不到机器，或状态是 `unauthorized`；`adb: device unauthorized`。
- **原因**：开发者选项没开、USB 调试没开、授权弹窗没点（或点了"拒绝"）。
- **解决**：
  1. 设置→我的设备→全部参数→**连点"MIUI 版本"7 次** → 更多设置→开发者选项；
  2. 打开 **USB 调试**（建议同时打开 **USB 调试(安全设置)**、**通过 USB 安装**）；
  3. 插线后手机上点 **允许**（勾"一律允许"）；没弹窗 → 开发者选项里"**撤销 USB 调试授权**"再重插；
  4. `unauthorized` 卡住时：102 上 `adb kill-server && adb devices`。

### ③ 开了调试模式，但点不动（坐标手势被拦）
- **现象**：`adb shell input tap 100 200` 报 `Injecting to another application requires INJECT_EVENTS permission`（A12 实测 rc=255）；AutoGLM / MobileAgent / mobile-mcp 这类**按坐标点**的方案全部失效。
- **原因**：小米在运行时抹掉了 `CAPABILITY_CAN_PERFORM_GESTURES`，且 `input` 走的注入被 SELinux/权限拦；`minitouch`/`sendevent` 同样被拦。
- **解决**（按优先级）：
  1. **用无障碍节点动作**（本项目的正解）：`pu.jar` 的 `click-id/click-desc/click-text/click-xy/settext/scroll` —— 不需要坐标注入、不需要 root；`click-xy` 是"按坐标找到节点再做无障碍点击"，能替代大部分坐标操作；
  2. 开发者选项里打开 **"USB 调试(安全设置)"**（部分 MIUI 允许模拟点击）后再测 `phone-doctor` 的 `input_inject`；
  3. 需要真坐标手势/改 supplicant 配置 → **刷 Magisk 用 root**（`su -c input tap` 实测可用，K20 Pro 就是这条路），`backend=root-input`；
  4. 装 App 走系统无障碍手势（AutoGLM/mobile-mcp 的路子）——但要接受额外安装与"无障碍服务被系统自动关闭"的维护成本。

### ④ 要安装 App + 开启无障碍（只有 App 型方案才需要）
- **现象**：`adb install` 报 `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`。
- **原因**：MIUI 拦截 adb 静默安装，必须在手机上确认；无障碍服务还要手动授权，且 MIUI 会在后台把它关掉。
- **解决**：
  1. 打开开发者选项里的 **"通过 USB 安装"** 与 **"USB 调试(安全设置)"**；
  2. 仍被拦 → 把 APK 推到 `/sdcard/Download/`，**手机文件管理里手动安装**（会弹安装确认）；
  3. 开无障碍：设置→更多设置→**无障碍→已下载的服务**→打开对应服务；
  4. **MIUI 会自动关闭无障碍服务** → 用例前用 `phone-doctor` 看 `accessibility` 项；失效就重新打开（我们遇到过"服务异常，重启一下"）；
  5. 说明：**本项目的免 root 方案（pu.jar）不依赖无障碍服务**，只有 Portal/MobileAgent 方案才需要，可按需跳过。

### ⑤ 状态不对就用不了（"某些状态不通过"）
- 现在 hub 直接告诉**为什么不可用**，不用猜：
  ```
  phone-hub ls                     # 每台: state / root / jar / wifi / capabilities
  curl -s 127.0.0.1:8901/devices/<sn> | python3 -m json.tool   # 看 usable / blockers[{msg,fix}]
  curl -s -X POST 127.0.0.1:8901/devices/<sn>/doctor           # 逐项体检 + 修法
  ```
| 状态 | 含义 | 处置 |
|---|---|---|
| `absent`(offline) | adb 看不到 / offline | 插线、换口、`adb kill-server`、USB 用途改 MTP |
| `unauthorized` | 手机没授权 | 手机上点允许；撤销授权后重插 |
| `usb_debug=false` | USB 调试没开 | 开发者选项打开 |
| `no_backend` | 无 root 且 pu.jar 不就绪 | 修 pu.jar（`build-pu-jar.sh`）或给 root |
| `busy`(using) | 被别人占用 | 等释放；`phone-hub release <sn>` |
| `low_battery` / `time_skew` / `screen_locked` | 会半途失败 | 插电 / 自动时间 / 解锁常亮 |

### ⑥ MIUI 已知限制（记录在案，别在这上面浪费时间）
1. **中文 SSID 不进 WLAN 列表**（`WifiGbk` 特判，如 `无线实验局`）→ 开放/PSK 用 `cmd wifi connect-network` 绕过；**企业级中文 SSID 目前无解**（要自建 APK 调 `WifiManager.addNetwork`）。
2. **设置里的下拉框**（安全性 / EAP 方法 / 阶段2 / CA 证书）**没有无障碍点击动作** → 不要走"手动添加网络"，从**扫描列表点 SSID**（AP 决定安全类型，不用改下拉框）。
3. **坐标手势被拦** → 见 ③。
4. **无障碍服务会被系统自动关闭** → 见 ④。
5. **列表按信号动态排序且只显示一部分** → 多 `scroll` 几轮，或用 `scan` 拿全量空口结果。

---

## 四、命令速查

```bash
# 体检（推荐第一步）
phone-doctor                       # 全部终端
phone-doctor 463fd7bf1220 --json    # 单台、机器可读
curl -s -X POST 127.0.0.1:8901/devices/<sn>/doctor

# 农场
phone-hub ls                       # 一览：state/root/jar/wifi/capabilities
phone-hub show <sn>                # 单台详情（含 blockers/usable）
phone-hub lease <sn> --owner me --ttl 900
phone-hub release <sn>
phone-hub exec <sn> -- wifi        # 用该终端跑一条原语

# 常用修法命令
adb -s <sn> shell svc power stayon true
adb -s <sn> shell wm dismiss-keyguard
adb -s <sn> shell input keyevent 224          # 唤醒（有 root 时才一定可用）
adb -s <sn> shell cmd wifi set-wifi-enabled enabled
adb kill-server && adb devices
```

## 五、加一台新机的判定线
**`phone-doctor` 全项没有 `fail` → 可用**（`warn` 可带着跑，但注意其 fix）。
- 免 root 机器：必须 `jar=✓`（pu.jar 就绪）才能点/输/滚；开放/PSK 还需要 Android 11+ 的 `cmd wifi`。
- root 机器：`backend=root-input`，坐标手势/按键/改配置全可用（jar 不是必需）。
- 两台现在都是 `ready`，可作为"接入合格"的样张：`463fd7bf1220`（免 root，jar 后端）、`57ada8`（root，root-input 后端）。

---

## 六、占用 / 释放 / 自动回收（硬闸）

**一句话**：占用 = 给这台手机挂"我在用"的牌子；**现在是硬闸** —— 别人持有效租约时，动这台手机的任何命令都会被拒（HTTP 409），直到对方释放、租约到期、或你强制收回。

| 动作 | 命令 / 页面 | 说明 |
|---|---|---|
| 占用 | `phone-hub lease <sn> --owner me --ttl 900` / 卡片「占用」 | 别人已占 → 拒绝并告诉你"谁占用、剩多久" |
| 心跳 | `phone-hub heartbeat <sn> --owner me` | 证明"人还在 / agent 还活着"，同时续期 |
| 释放（自己的） | `phone-hub release <sn> --owner me` / 卡片「释放」 | **只能释放自己的**；别人的会被拒 |
| 强制收回 | `phone-hub reclaim <sn> --reason "…"` / 卡片「强制收回」 | 打断占用者、把终端拿回来（会记录"上次收回：谁 + 原因"） |
| 执行（受硬闸约束） | `phone-hub exec <sn> --owner me -- <原语>` | 别人持租约 → 409；`--force` 可强闯 |

**自动回收（防"占用后没人释放"）** —— hub 后台每 10s 巡逻，满足任一条件就收回并把终端放回空闲：
1. **租约到期**（TTL，默认 900s）；
2. **无心跳且无动作** 超过 `PHONE_HUB_IDLE_RECLAIM`（默认 600s）→ 判定 agent 已死 / 页面已关；
3. **心跳还在、但设备长时间没有任何动作** 超过 `PHONE_HUB_STALL_RECLAIM`（默认 300s）→ 判定 **LLM 服务器挂了 / 任务挂死**
   （这是最容易漏的一种：进程没死、心跳照跳，只有"设备真的没被操作过"能识别。超过 `PHONE_HUB_STALL_AFTER`(120s) 起就在设备详情里标 `stalled=true` 并给出"还有多少秒被收回"）；
4. **屏幕指纹长时间无变化**（且最近无动作）超过 `PHONE_HUB_STILL_RECLAIM`（默认 900s）→ 僵尸占用。

> 注意设计要点：**心跳不刷新"最后活动时间"** —— 只有真正操作设备（`exec`）才算活动；
> 正在执行的长动作会记 `exec_inflight`，巡逻不会把它误判成卡死。

阈值改 `/usr/local/share/phone-hub/hub.env` 后 `systemctl restart phone-hub` 生效。演示过的实测：
- 停掉心跳 → **67s 自动收回**（阈值临时 60s）；
- **心跳照跳、设备 91s 无动作 → 自动收回**，原因写明"心跳仍在但设备 91s 无任何动作（LLM 卡住或任务挂死）"（阈值临时 90s）。

**agent 侧的保险（不只靠 hub）**：
- 单次 LLM 调用 `PHONE_AGENT_LLM_TIMEOUT=120s` + 重试 2 次，失败即收口（判 `LLM_DOWN`）并**释放终端**；
- 单任务总时限 `PHONE_AGENT_DEADLINE=1200s`，到点收口释放；
- **异步作业**：`POST /tasks` 立刻拿 `job_id` → `GET /tasks`、`GET /tasks/<id>` 查进度 → `POST /tasks/<id>/cancel` **一键取消并释放**（LLM 挂住时用这个）。

**同一台手机被连说两句会怎样**：第二个请求**排队等**（`PHONE_AGENT_QUEUE_WAIT=600s`），状态先 `queued` 再 `running`，而不是立刻报错；不同手机则真并行。


**agent 的自动行为**（不用你操心）：每次任务它会先**自动占用**目标终端并持续心跳（每 30s），任务结束**自动释放**；多台扇出时每台一个 owner（`phone-agent-fanout:<serial>`）。遇到被占用它会**先去挑空闲的终端**，需要抢才向上层报告。

**被人占用时怎么办**：先在手机墙看 owner 与剩余时间 → 多数情况**换一台空闲的**；确认对方是死任务（心跳很旧/显示"疑似僵尸"）才点「强制收回」。

