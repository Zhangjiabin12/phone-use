> **硬规则（挑终端）**：只对 `usable=true` 且 `stf_state=available` 的终端派活（数据来自 8901 `GET /devices`）；`usable=false` 时不要硬跑，把它的 `blockers`（含修法）原样报给用户。被别的 owner 占用会返回 409，换一台空闲的。
# phone-use-wlan —— 用一句话让 AI 把手机连上 WiFi / 完成认证

> 这个文件是**给 AI 看的 runbook**，不是给人执行的操作手册。AI 读到它 + 拿到 `phone-use` 原语，
> 就能自己看环境、自己决定怎么做（像 browser-use 那样），而不是跑一条写死的脚本。

## 0. 输入输出约定
- 输入：一句自然语言，例如
  - 「连接 diag-lab，不认证」
  - 「连 928wpa2-psk，密码 12345678」
  - 「连 HY-CJ1-WPA2-L 做 1X 认证，账号 hx 密码 123456」
  - 「连 test-portal2 做 portal 认证，账号 zjb 密码 123456」
  - 「现在连的什么？」「断开」「忘记 diag-lab」
- 输出：**成功/失败 + 证据**。证据至少包含：SSID、BSSID、频点、RSSI、MAC、IP、安全类型；
  失败时加：`level2FailureCode` / `level2FailureReason`（1X）或门户响应码；并给一张截图路径。

## 1. 原语（`phone-use <命令>`，输出都是 JSON）
| 命令 | 用途 |
|---|---|
| `state` | 设备型号 / 是否 root / 当前 Wi-Fi / 已保存网络数 |
| `wifi` | 当前连接事实（ssid/bssid/mac/ip/freq/rssi/security_type/supplicant/validated） |
| `list` / `scan [关键字]` | 已保存网络 / 空口扫描（可筛 `EAP`、`WPA2-PSK`） |
| `probe [url]` | 探测是否被门户拦截（默认 `http://1.1.1.1/`）→ `portal_intercepted` |
| `wifi-connect <ssid> <open\|owe\|wpa2\|wpa3> [密码] [--bssid MAC] [--mac none\|auto]` | 开放/PSK 上线（**不支持 EAP**） |
| `wifi-forget <ssid\|netid>` / `wifi-forget-all` / `wifi-radio on\|off` | 清理与开关 |
| `ui [过滤]` / `find <子串>` | 元素树（text/id/desc/bounds/click/edit） |
| `click-text\|click-desc\|click-id <子串> [--self]` | **节点点击**（`--self` = 点元素本身，WebView 元素需要） |
| `click-xy <x> <y>` | 按坐标找节点再无障碍点击（**替代被封的坐标手势**） |
| `settext [--id <元素id>] <文本>` | 输入（WebView 输入框用 `--id`） |
| `scroll [n]` / `scroll-up [n]` | 无障碍滚动 |
| `global <home\|back\|recents\|notifications>` | 系统动作 |
| `shot <设备路径>` + `pull <设备路径> <本地>` | 截图取证 |
| `http <url>` / `httpfile <url> <设备路径>` | **手机自己**发 HTTP（认证必须由手机的 IP/MAC 发起） |
| `shell <命令>` | 以 shell 身份执行（`cmd wifi …`、`dumpsys …`、`am start …`） |
| `failure [ssid]` | 取最近一次连接失败码 |
| `jar <pu.jar 命令行>` | 兜底：直接下原语（`ui/click-*/settext/portal-login/scroll/…`） |

## 2. 成功判据（**不要看命令返回值**）
```
cmd wifi connect-network 永远回 "Connection initiated" —— 不能当成功
```
- **上线成功**：`phone-use wifi` → `ssid` 等于目标 且 `supplicant=COMPLETED` 且 `ip` 非空
- **1X 成功**：同上 + `phone-use failure <ssid>` → `level2FailureCode=NONE`
  失败：`AUTHENTICATION_FAILURE` / `level2FailureReason=AUTH_FAILURE_EAP_FAILURE`
- **门户认证成功**：`phone-use probe` → `portal_intercepted=false`
- **门户认证失败**：`probe` 仍被拦（location 含 `/portal/`），或门户返回 `{"code":…,"message":…}`

## 3. 四条路线（AI 自行组合，遇阻就换招）

**0. 开局预检（必做，别跳过）**
0.5 **终端状态可疑（不在列表/unauthorized/offline/点了没反应/电量低/时间不对）→ 先体检**：
    `phone_exec <serial> ["shell","…"]` 前先让上层或自己走一次体检端点（`POST /devices/<serial>/doctor`），
    或让人在 102 上跑 `phone-doctor <serial>`；它会逐项给出**结论 + 修法**（数据线/调试模式/坐标注入被拦/
    安装受限/无障碍/常亮/电量/时间同步/MIUI 限制）。**体检不过就别硬跑用例**，把 blockers 连同修法一起报给用户。
    完整清单见 `/usr/local/share/phone-use/ONBOARD.md`（新机接入 10 步 + 每个坑的解决）。
1. `phone-exec state` → 看当前连的谁、有没有 root、**backend**（root-input 有坐标手势；jar-node-action 只有节点动作）
2. `phone-exec scan <目标SSID>` → **空口到底有没有这个 SSID**
   - 空口没有 → 若目标需要认证且是中文 SSID，直接 `RESULT: FAIL`（写明"该终端位置扫不到该 SSID"，附 scan 结果）；**不要**去"手动添加网络"硬凑
   - 空口有、但设置列表里滚不到（MIUI 列表按信号动态排序/只显示一部分）→ 用 `scan` 拿 BSSID，再回到列表多滚几轮；仍找不到就 FAIL 并说明
3. **同一个动作连续 2 次没有新信息 → 换招**（改路线/改原语/改终端）；**任何路线连续 3 次无果 → 立刻收口**：释放终端、输出 `RESULT: FAIL` + 已试过的证据（别把步数烧光）
4. **一旦核验成功就收口**：不要再"顺手"忘记网络/重配/多试几种；直接释放终端并输出 `RESULT: PASS` + 证据（多做的动作会毁掉刚建立的现场）
5. **占用是硬闸**：别人持有效租约时你的 `phone_exec` 会被拒（409，并告诉你谁占用、剩多久）。
   你自己动手前会**自动占用 + 心跳**，结束**自动释放**；指定了终端而它正忙时，你会**排队等**（默认最多 600s）。
   被占用太久才向上层报告要 `reclaim`（收回会打断对方，别擅自做）。
   注意：长期无心跳无动作（默认 600s）、**心跳在但设备长时间没动作（默认 300s，典型=LLM 服务器挂了/任务挂死）**、
   以及屏幕长期不动的僵尸占用（默认 900s）都会被 hub **自动收回**。
6. **别让自己变成"占机不干活"**：任务总时限 1200s、单次 LLM 调用 120s（重试 2 次）——超时就收口释放；
   需要人工中止时，上层可以 `POST /tasks/<job_id>/cancel`（你会在下一步立刻收口）。


**A. 开放 / 不认证**
1. `phone-use wifi-connect <ssid> open --mac none`
2. `phone-use wifi` 轮询到连上 → 3. `phone-use probe`
   - 未被拦 → PASS
   - 被拦且用户要求认证 → 转 C

**B. PSK**
1. `phone-use wifi-connect <ssid> wpa2 <密码> --mac none`（要固定设备 MAC 就 `--mac none`，随机就 `auto`）
2. 轮询 `wifi`；失败看 `failure <ssid>`
> 密码错的表现：目标 SSID 一直不上线，且回落旧网络（`dumpsys wifi` 里 `HandshakeState→DisconnectedState` 循环）

**C. 门户认证（**第一步永远先试协议式**，与厂商/浏览器无关）**

> **C0（优先）：协议式**
> ```
> phone-use jar portal-login <账号> <密码>     # 迈普门户；也支持 portal-free / portal-noper
> ```
> 成功判据：返回 `{"code":"0","message":"NO_ERROR"}`，且随后 `probe` 不再被拦（302→301 之类）。
> **为什么优先**：界面式依赖"厂商把门户入口放哪、用什么浏览器打开、表单暴不暴露给无障碍"，
> 换个手机就变。实测华为 nova 9（EMUI/鸿蒙）：门户入口是**系统通知「点击进行登录/认证」**，
> 点它开的是**华为浏览器**（`com.huawei.browser/.customtab.BrowserCustomTabActivity`），
> AOSP 的 `com.android.captiveportallogin` **被禁用**（`am start -n` rc=255，
> `resolve-activity -a android.net.network.CAPTIVE_PORTAL_LOGIN` → No activity found），
> 而且该页表单**没进无障碍树**（`ui account`=0、`find 帐号|密码`=0）→ 界面式根本填不进去。
> 同一台机器走 C0（`jar portal-login zjb 123456`）→ `{"code":"0","message":"NO_ERROR"}` 一次成功。
>
> **C1（协议式不适用时才走界面式）**：先探"厂商门户入口在哪"，三选一：
> ① 通知栏里有「点击进行登录/认证」类通知 → 点它（华为/部分国产 ROM）；
> ② 有 AOSP `captiveportallogin`（`resolve-activity -a android.net.network.CAPTIVE_PORTAL_LOGIN` 有结果）
>    → WLAN 页点「登录到网络」或直接 `am start -n com.android.captiveportallogin/.CaptivePortalLoginActivity -d <门户URL>`；
> ③ 都没有 → 用浏览器打开门户 URL：`am start -a android.intent.action.VIEW -d '<门户URL>'`。
> 进到门户页后 `ui` 找表单（有 HTML id 的 WebView 能被无障碍读到，如 `account`/`acc_pass`/`widget-login-btn`），
> 用 `click-id !<id>` + `settext --id <id> <值>` 填；**读不到表单元素就立刻回退到 C0/报告 FAIL**，别硬耗步数。

1. 先按 A 连上开放网络，`phone-use probe` 确认被拦（响应里能看到 `wlanusermac` 等网关参数）
2. `phone-use shell am start -a android.settings.WIFI_SETTINGS`
3. `phone-use click-desc 登录到网络`（找不到就 `scroll 3` 再试）→ 进 **系统门户登录页**
   （`com.android.captiveportallogin` 的 WebView **会把网页元素暴露给无障碍**，带 HTML 原 id）
4. `phone-use ui` 找入口：
   - 「我要上网」→ `click-id !widget-login-btn`
   - 表单 → `click-id account` → `settext --id account <账号>`
     → `click-id acc_pass` → `settext --id acc_pass <密码>` → `click-id account-login-btn`
   - 免费/一键上网类按钮：`ui` 里找文本（如 一键上网/免费上网）再点
5. `phone-use probe` 复核；仍被拦就 `ui` 看错误提示并重试/截图
6. 兜底（迈普门户，快且带服务端错误码）：`phone-use jar portal-login <账号> <密码>`
   （也支持 `portal-free` / `portal-noper`；成功回 `{"code":"0","message":"NO_ERROR"}`）

**D. 1X（802.1X / PEAP+MSCHAPv2）**
> `cmd wifi` 不支持 EAP，**只能走 UI**；好在从扫描列表点企业级 SSID 时不需要改下拉框
1. `phone-use scan EAP` 看空口有哪些企业级 SSID、选最强的
2. `phone-use shell am start -a android.settings.WIFI_SETTINGS`
3. `phone-use click-desc <ssid>`；没命中就 `scroll 3` 重试（列表按信号动态排序且只显示一部分）
4. `phone-use ui` 确认出现 `com.android.settings:id/identity`（凭据弹窗）
5. `settext --id com.android.settings:id/identity <账号>`
   `settext --id com.android.settings:id/password <密码>`
   `click-id android:id/button1`（连接）→ **系统会自动开始连它**
6. 轮询 `wifi`；成功/失败按第 2 节判据；失败必看 `failure <ssid>`
7. 若没自动连：`shell cmd wifi set-wifi-enabled disabled` → `enabled` 触发重选
   （注意：其它已保存网络/`network suggestion` 会抢，必要时 `wifi-forget`/`shell cmd wifi remove-all-suggestions`）

## 4. MIUI/HyperOS 实测坑（2026-10-16，Redmi M2010J19SC / MIUI 14 / Android 12）
1. **坐标手势被 ROM 封**：`input tap`、`sendevent`、minitouch、`dispatchGesture` 全部无效
   （系统运行时抹掉 `CAN_PERFORM_GESTURES`）→ 一律用**节点动作**（`click-*`/`settext`/`scroll`）
2. **设置里的 Spinner 下拉没有无障碍点击动作**（`performAction(ACTION_CLICK)=false`，父链也无可点节点）
   → 改不了「安全性 / EAP 方法 / 阶段2 / CA 证书 / 隐私」。所以**手动添加网络**这条路走不通；
   走"扫描列表点 SSID"就不需要它
3. **中文 SSID 不进 WLAN 列表**（MIUI `WifiGbk` 特判，如 `无线实验局`）→ 开放/PSK 可以用 `cmd wifi`
   绕过；**企业级中文 SSID 暂时无解**（要自建 APK 调 `WifiManager.addNetwork`）
4. **`network suggestion` 会自动拉起网络**（如 `diag-lab`）干扰选网 → `shell cmd wifi remove-all-suggestions`
5. **列表不稳定/不完整**：每次刷新显示的网络集合都不同 → 用 `scroll` 多翻几轮，或用 `scan` 拿全量
6. 手机会休眠 → 先 `shell svc power stayon true`
7. `forget-network` 需要 **netid**（用 `list` 查），传 SSID 时本工具会自动转换

## 5. 机型边界（选型用）
| 系统 | 选网/锁BSSID/固定MAC | PSK | 1X（UI） | 门户（UI） | 坐标手势 |
|---|---|---|---|---|---|
| Android 12 / MIUI 14（M2010J19SC） | ✓ 免 root | ✓ | ✓（HY-CJ1-WPA2-L / hx / 123456 实测通过） | ✓（test-portal2 / zjb / 123456 实测通过） | ✗ |
| Android 13 / HyperOS（Note 11 Pro） | ✗ 需 root 或账号开关 | ✗（同上） | 未测 | ✓ | ✗ |
| 已 root（K20 Pro） | ✓ | ✓ | ✓ | ✓ | ✓ |

## 6. 反面清单（别做）
- 别用命令返回值判成功（见第 2 节）
- 别写死某个门户的协议（用 C 的通用 UI 路径；协议式只作兜底）
- 别用坐标手势（被 ROM 封）；别依赖下拉框
- 别在没证据的情况下报成功：每次都要带 SSID/BSSID/IP/MAC/失败码 + 截图路径

---

## 怎么看 / 怎么点（视觉与点击手册 · 给 agent 的硬规矩）

### 一、看屏幕：只能用 `phone-look`（agent 的工具输出是文本，看不到图）
```bash
phone-look <serial> "现在是什么页面？有没有需要先处理的弹窗？"     # 回文本结论
phone-look <serial> --coord "WLAN 列表里 'test-portal2' 这一项"   # 额外给 TAP=x,y
```
- 它内部做：`screencap → 取回本地 → 交给视觉模型（deepseek-flash，已实测能准确读真机截图）→ 回文本`
- 结论里若带 `TAP=x,y`，就是可直接点的**设备绝对坐标**
- 想要原始截图存档（备查/给人看）：`phone-use shot /sdcard/s.png` + `phone-use pull /sdcard/s.png /tmp/s.png`
- **坐标永远是设备真实分辨率**（先 `phone-use state` 读 `screen`）：华为 1236×2676、小米 1080×2340 —— **别猜**

### 二、点屏幕：三级精度，从上到下选（能用上面的就别用下面的）
| 级别 | 命令 | 什么时候用 |
|---|---|---|
| ① 语义点击（最稳） | `phone-use click-text "登录"` / `click-desc "下一步"` / `click-id !account` | 控件有文字/描述/id（设置项、按钮、WebView 表单） |
| ② 元素定位（推荐默认） | `phone-use find "WLAN"` / `ui WLAN` → 拿到 `bounds` → 算中心 → `phone-use click-xy X Y` | 有控件但文字不唯一；**P3 机型（只能节点动作）也只有这条路** |
| ③ 视觉估坐标 | `phone-look --coord "…"` → `phone-use tap X Y` | 自绘界面 / WebView 不暴露元素 / 上面两条都失败时 |
- 输入文字：`phone-use settext --id !account "zjb"`（优先）或 `phone-use input "文本"`；有 root 也可 `key`
- 按键：`phone-use key back|home|app_switch|enter…`；**不要用 `adb shell input`**（MIUI/HyperOS 会被 `INJECT_EVENTS` 拦；`phone-use` 会自动按 P1 root / P2 input / P3 jar 回退）

### 三、判定纪律（不许拿返回码当成功）
- 上线成功 = `wifi` 里 **ssid 匹配 + supplicant=COMPLETED + ip 非空**
- 1X 成功 = 同上 **+ `failure` 里 level2FailureCode=NONE**
- 门户成功 = `probe` 里 **portal_intercepted=false**（普通公网地址 302→301；`generate_204` 可能被 permit 名单放行成假 204，**不能当证据**）
- 连续 2 次同类失败 → 换招或如实报 FAIL，不要卡在同一步重复

### 四、改东西的规矩（底层冻结）
- `/opt/phone-use/base/**` 是**已跑通的底层，只读**：`phone-use`、`SKILL.md`、`ONBOARD.md`、hub/服务代码 —— **禁止编辑**
- 要改必须先复制再改：`cp /opt/phone-use/base/X /opt/phone-use/work/copies/X.<时间戳>`，改那份（默认不生效，作为提案）
- **自适配请写数据，不要写代码**：把新机型差异追加到 `/opt/phone-use/work/adapt/<机型>.yaml`，例如
  ```yaml
  HUAWEI-BRQ-AN00:
    cmd_wifi_connect: false      # HyperOS/部分鸿蒙不允许 shell 连网 → 走界面或门户协议式
    input_backend: input         # 免 root 但允许坐标注入
  ```
- `phone-use` 启动时会做 base 的 sha256 校验；**校验不过就拒绝执行**（防止"偷偷改了底层"）

### 五之补：实测踩坑（2026-10-16，agent 自己发现并记录）
1. **残留会话会让 `probe` 假报"未被拦截"**：开局若残留上次的 L2 连接，`probe` 可能显示 `portal_intercepted=false`，
   但手机真实拉网页会 DNS 失败 —— **判据要看真实内容**（163.com/neverssl 返回真实 HTML），不能只看 probe。
2. **`jar portal-login` 可能被 permit 名单短路**：它先探 `1.1.1.1`，若该地址在门户 permit 名单里被放行返回 301，
   就判"无需认证"而**根本不发登录请求**。此时要**重置客户端身份**触发真正的门户挑战：
   `wifi-forget <ssid>` → `wifi-connect <ssid> open --bssid <MAC> --mac none` → `captive_portal_flag` 变 true → 再 `portal-login`。
3. **MIUI 忽略 `--mac auto`**（MAC 不变）→ 换会话只能靠 forget + 重连（锁定 BSSID 更稳）。
4. `phone_exec` **会自动占用**终端：不要再显式 `lease_device` 后再 `phone_exec`（会 409）。
