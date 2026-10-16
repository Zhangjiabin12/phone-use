# phone-use · 手机农场（非 root 也能跑）

把一堆真机安卓手机变成一个**可编排的测试农场**：在浏览器里看画面、按键、点屏幕，**用一句中文让它自己连 WiFi / 做 Portal / 1X / PSK 认证**，并**必须回报成功或失败 + 证据**。

> 设计原则：**不 root、不装 App、不要账号**；能力按优先级回退；所有判定都要有可验证的证据，测完不留垃圾。

---

## 1. 能干什么（一句话示例）

```bash
phone-agent "连 test-portal2 做 portal 认证，账号 zjb 密码 123456，认证完确认能上外网"
phone-agent "两台一起连 928wpa2-psk 密码 12345678"          # 多机并行
phone-agent "连 HY-CJ1-WPA2-L 做 1X 认证，账号 hx 密码 123456"
phone-agent "体检一下 57ada8"                                # 新机接入体检
```

上层只给「**一句话 + 可选终端范围**」，其余（挑机器、连网、点界面、判定、取证）全由 agent 现场决定。

---

## 2. 架构与端口（89xx 手机农场段）

| 端口 | 服务 | 作用 | 给谁用 |
|---|---|---|---|
| **8910** | `phone-wall` | **手机墙**：高清画面（内嵌 scrcpy H.264）+ 按键条 + 一句话派任务 + 体检面板 + 占用/释放/接管 | **人（主入口）** |
| **8902** | `phone-agent` | **一句话总入口**：LLM agent 自己看环境、自己连、回报 PASS/FAIL + 证据（支持异步作业、取消、多机并行） | 人 / 平台 |
| **8901** | `phone-hub` | **农场 API**：终端清单 / 能力集 / 版本 / **租约硬闸** / 体检端点 / `exec` 原语 | 程序（agent 后端） |
| 8000 | `ws-scrcpy` | H.264 视频流后端（被墙内嵌，一般不用直接开） | 只给墙调用 |

```
人 ──► 8910 手机墙 ──┐
                    ├──► 8901 phone-hub ──► adb ──► 真机
平台 ─► 8902 agent ──┘
                    8000 ws-scrcpy（视频流，被 8910 内嵌）
```

---

## 3. 核心难点：**非 root 怎么点屏幕**（三种后端，按优先级回退）

安卓上「用电脑点手机」有三条路，本项目的 `backend()` 会**自上而下探测并回退**：

| 档位 | 名称 | 探测条件 | 能做什么 | 做不到 |
|---|---|---|---|---|
| **P1** | `root-input` | `su -c id` 成功 | 坐标点击/手势/按键/输入、改系统配置、装 APK | 需要刷机 |
| **P2** | `input` | 实测 `adb shell input tap 1 1` 返回 0（系统没拦 `INJECT_EVENTS`） | 坐标点击/滑动/按键/输入 | 没有 su，改不了系统配置 |
| **P3** | `jar-node-action` | 能跑 `uiautomator runtest pu.jar` | **无障碍节点动作**：找控件点、输入文字、滚动、全局动作、截图、手机自己发 HTTP | **不能按坐标**（点不到没有可点节点的控件，如设置里的下拉框） |

**为什么要有 P3**：小米 MIUI/HyperOS 把 shell 的坐标注入封了（`SecurityException: Injecting to another application requires INJECT_EVENTS permission`），minitouch/sendevent 也一并被封。于是我们**不装 APK、不开无障碍服务**，改用设备自带的 `uiautomator` 跑一个自写 jar（`pu.jar`），通过 `UiAutomation` 拿到元素树并做节点动作。

与之**独立**的另一件事是「**能不能自动连网**」：靠 Android 11+ 的 `cmd wifi connect-network`，不同 ROM 权限不同 ——
- MIUI 14 / Android 12：可用 ✓
- HyperOS / Android 13：`SecurityException: Uid 2000 does not have access to connect-network wifi command` ✗

**本项目口径**：要**无人值守**就必须能自动连网，**不能自动连网 = 判定为不可用**（`usable=false`），并把阻塞原因与修法一起报出来。

---

## 4. 实测过的机型（能力矩阵）

| 机型 | 系统 | root | 后端 | 坐标点击 | 自动连网 | 结论 |
|---|---|---|---|---|---|---|
| 小米 M2010J19SC | MIUI 14 / Android 12 | ✗ | `jar-node-action` | ✗（用节点点击代替） | ✓ | 可用 |
| Redmi K20 Pro | MIUI 12.5 / Android 11 | ✓ | `root-input` | ✓ | ✓ | 可用 |
| 华为 nova 9 (BRQ-AN00) | EMUI 14.2 / Android 12 | ✗ | `input` | ✓（含滑动/按键） | ✓ | 可用 |
| 红米 Note 11 Pro | HyperOS / Android 13 | ✗ | —— | —— | ✗ | **不可用**（HyperOS 拒绝连网命令） |

> 华为这台是农场里**第一台「免 root 但能坐标注入」**的机器 —— 说明"非 root 就一定点不了坐标"是错的，得**逐机实测**。

---

## 5. 门户认证：**协议优先**（踩过的坑）

同一台华为，界面式与协议式结果完全不同：

```
界面式（失败）：
  · 门户入口是【系统通知】「点击进行登录/认证」，点它打开【华为浏览器】
  · AOSP 的 com.android.captiveportallogin 被禁用（resolve-activity 无结果、am start rc=255）
  · 华为浏览器里的门户页表单【没进无障碍树】（ui account=0）→ 填不进去 → agent 耗尽步数

协议式（一次成功）：
  phone-use jar portal-login <账号> <密码>
  → {"code":"0","message":"NO_ERROR"}，复核 http://1.1.1.1/ 由 302 变 301（不再被拦）
```

**所以 runbook 里写死：Portal 认证先走协议式（与厂商/浏览器无关），界面式仅在能读到表单时使用；读不到就立刻回退或报 FAIL，不许硬耗。**

同类的"别信返回码"判据：**成功 = 门户不再拦截（普通公网地址 302→301、`Location` 不含 `/portal/`）**；`generate_204` 这类探测 URL 会被门户 permit 名单放行成假 204，**不能当成功证据**。

---

## 6. 文件说明

```
phone-use/
├── README.md                     # 本文件（架构/难点/机型矩阵/限制）
├── src/                          # 全部服务源码
│   ├── phone-use.py              #   原语 CLI（tap/swipe/ui/find/scan/wifi/probe/jar…）
│   ├── phone-hub.py              #   农场 API + 租约硬闸 + 体检端点（:8901）
│   ├── phone-hub-mcp.py          #   给 MCP 客户端的最小工具面
│   ├── phone-agent.py            #   一句话总入口，LLM agent（:8902）
│   ├── phone-doctor.py           #   新机接入体检（人话结论 + 怎么修）
│   ├── wall/                     #   手机墙（:8910）
│   │   ├── phone-wall.py
│   │   └── wall-page.html
│   └── jar/                      #   注入 jar：build-pu-jar.sh + Java 源码
├── deploy/                       # 部署物
│   ├── install-all.sh            #   幂等部署（上传到 /tmp 后一条命令装完）
│   ├── phone-farm                #   统一入口：status/start/stop/restart/logs/config/doctor
│   ├── farm.env                  #   ★ 唯一配置文件（端口/租约阈值/agent 参数）
│   ├── hub.env / agent.env       #   细项覆盖
│   └── units/*.service           #   systemd 单元
├── tools/                        # pu-node.py、pu-find.py（jar 辅助脚本）
├── docs/                         # 文档与截图
│   ├── ONBOARD.md                #   新机接入清单（10 步 + 六类坑）
│   ├── SKILL-phone-use-wlan.md   #   给 agent 的 runbook（8901 /skill 供出）
│   └── img/                      #   实测证据截图
└── legacy/                       # 已淘汰组件（旧单机投屏等）
```

---

## 7. 快速开始

```bash
# 1) 依赖：adb、python3、usb 直连（或 adb over tcp）
adb devices

# 2) 部署（幂等，可重复跑；配置只改 deploy/farm.env）
scp src/*.py src/wall/* deploy/*.env deploy/phone-farm deploy/units/*.service docs/*.md tools/pu-node.py root@<host>:/tmp/
ssh root@<host> bash /tmp/install-all.sh

# 3) 体检一台新机（人话结论 + 怎么修）
phone-doctor <serial>

# 4) 手机墙
phone-farm status            # 统一看服务/端口/终端/墙地址

# 5) 一句话下单（或直接在手机墙上输入）
phone-agent "连 928wpa2-psk 密码 12345678"
```

---

## 8. 租约：防止"占着不放"

农场是多个人/多个 agent 共用的，所以有**硬闸**：

- `exec` 时若已被**其他 owner** 持有**活租约** → 直接 **409**（不是靠自觉）
- **心跳 ≠ 设备活动**：只有真正操作设备才更新 `last_active`，心跳单独记 —— 否则"agent 死了但心跳还在"会永远收不回
- 回收规则（阈值在 `hub.env`）：TTL 到期 / 心跳停 / **心跳仍在但设备长时间无动作**（LLM 卡死）/ 屏幕长时间没变
- 手机墙上有「**接管**」：人可以在 agent 跑任务时收回终端自己点（会打断该任务，有二次确认）

实测：僵死 owner（`dead-agent`）在 91s 被收回，理由「心跳仍在但设备 91s 无任何动作」。

---

## 9. 已知限制（照实写）

- 手机墙的按键/点屏走 `input keyevent` / 节点动作；**P3 机型按不了坐标**，只能用节点点击
- MIUI 特有问题：中文 SSID 不进 WLAN 列表（`WifiGbk`）、Spinner 下拉框点不动（`performAction` 返回 false）
- Huawei/HyperOS 的门户认证入口与 AOSP 不同（见 §5），**别指望界面**
- `ws-scrcpy` 端口写死在 bundle 里（`--port`/环境变量都无效），固定 8000；手机墙会自动对准
- 画面帧率取决于通道：内嵌 scrcpy H.264 = 视频级；截图流（`screencap`）只有 1~3fps
---

## 10. Agent 主体：Qwen Code（2026-10-16 起）

原来那个手搓的 6 工具循环已退役；**脑子换成通用 coding agent**，`phone-use`/`phone-hub` 作为它的「手」和「闸」保留不变。

### 为什么换
"自己连、出问题自己排查、自己适配"需要的正是 **跑 shell + 读写文件 + 多步自修复** —— 这是 coding agent 的本职；
手机 GUI agent（AutoGLM / mobile-use）的强项只是"用眼睛点屏幕"，且 AutoGLM 的动作集**没有 shell/文件能力**。

### 分层
```
【脑子】Qwen Code（phonebot，非 root、无 sudo；项目级 .qwen 配置）
【眼睛】原生读图（补 models.dev 注册表的 modalities.image）+ phone-look 兜底
【手】  phone-use 原语（P1 root / P2 input / P3 jar 自动回退）· phone-look
【闸】  phone-hub（租约硬闸 / 排队 / usable / 体检 / 留痕）
【底层】/opt/phone-use/base 只读 + sha256 守卫；改动只能 cp 到 work/copies/
```

### 入口
```bash
pu-run "连 test-portal2 做 portal 认证，账号 zjb 密码 123456" [--timeout 900]
# 一次运行留三份档：logs/run-<ts>.jsonl（全事件轨迹）/ .md（人读摘要）/ .err（stderr）
```

### 关键工程细节（都踩过坑）
| 项 | 结论 |
|---|---|
| 系统提示词 | 项目级 `.qwen/system.md`（= docs/AGENT-PROMPT.md），含"看只能 phone-look、点只能 phone-use、底层只读、先复制再改、输出 PASS/FAIL+证据" |
| MCP | 项目级 `settings.json` 的 `mcpServers.phone-hub` → `phone-hub-mcp.py`（轨迹里可见 `phone-hub {}` 被调用） |
| 视觉 | qwen 按 `~/.qwen/model-registry.json`（models.dev）的 `modalities.image` 决定要不要把图给模型；该表**缺 deepseek-flash** → 用 `ops/fix-vision-registry.sh` 幂等补上（实测补完能原生读真机截图） |
| 轨迹 | `--output-format json` 有效（输出是**一个 JSON 数组**）；`--json-file` 无效 |
| 只读保证 | 以 root 跑靠 sha256 守卫（篡改 → exit 90）；以非 root 跑是物理只读 |
| 临时文件 | 给 agent 的 prompt 文件必须放它能读的地方（`mktemp` 建的 root 600 会让它收到空 prompt） |

### 复现
```bash
# 1) 冻结底层（只读 + 指纹清单 + 守卫启动器）
bash ops/install-frozen-base.sh        # 生成 /opt/phone-use/base 与 sha256
# 2) 装 agent 主体
bash deploy/install-qwen-agent.sh      # 建 phonebot、装 qwen、项目级 .qwen、pu-run、视觉补丁
```
