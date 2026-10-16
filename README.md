# phone-use

用一句话驱动真机安卓手机完成 WLAN 测试任务，并返回结论与证据。

```
输入  连 test-portal2 做 portal 认证，账号 zjb 密码 123456
输出  RESULT: PASS
      证据：SSID / BSSID / 频点 / RSSI / MAC / IP / 认证返回码 / 外网核验 / 截图路径
      轨迹：/opt/phone-use/pu/logs/run-<ts>.jsonl
```

## 1. 环境要求

| 项 | 要求 |
|---|---|
| 主机 | Linux，systemd，Python 3.10 以上 |
| 手机 | 数据线连接并授权 USB 调试；无需 root，无需安装应用 |
| 模型 | OpenAI 兼容接口，默认 `deepseek-flash` |
| 依赖 | `adb`、`curl`、`node` |

## 2. 安装

```bash
# 1) 部署服务
scp src/*.py deploy/*.env deploy/phone-farm deploy/units/*.service \
    deploy/install-all.sh deploy/install-frozen-base.sh \
    docs/SKILL-phone-use-wlan.md docs/ONBOARD.md tools/pu-node.py root@<host>:/tmp/
ssh root@<host> bash /tmp/install-all.sh

# 2) 冻结底层并生成校验清单
ssh root@<host> bash /tmp/install-frozen-base.sh

# 3) 安装任务主体并生成项目级配置
scp deploy/install-qwen-agent.sh root@<host>:/tmp/
ssh root@<host> bash /tmp/install-qwen-agent.sh
```

安装后填写模型密钥：编辑 `/opt/phone-use/pu/.qwen/settings.json` 中的 `env.OPENAI_API_KEY`。

## 3. 启动与状态

```bash
phone-farm start               # 启动全部服务
phone-farm status              # 服务、端口、终端就绪情况
phone-farm logs phone-agent    # 查看服务日志
phone-farm config              # 查看生效配置
```

端口与页面：

| 端口 | 用途 |
|---|---|
| 8910 | 浏览器界面：查看画面、按键、派任务、体检 |
| 8902 | 一句话任务接口 |
| 8901 | 终端清单、能力集、占用状态、体检接口 |
| 8000 | 手机画面视频流，由浏览器界面内嵌 |

浏览器访问 `http://<host>:8910/`。

## 4. 使用

### 4.1 一句话任务

```bash
phone-use "连 test-portal2 做 portal 认证，账号 zjb 密码 123456"
phone-use "连 928wpa2-psk 密码 12345678"
phone-use "连 HY-CJ1-WPA2-L 做 1X 认证，账号 hx 密码 123456"
phone-use "体检一下 57ada8"
```

参数：

| 参数 | 说明 |
|---|---|
| `--device <serial>` | 指定终端；省略时自动选择空闲可用终端 |
| `--timeout <秒>` | 运行超时，默认 900 |
| `--no-trace` | 不保存轨迹 |
| `--user <用户名>` | 运行任务主体所用的系统用户，默认 `phonebot` |
| `logs [时间戳]` | 查看历史运行的摘要与事件 |

每次运行在 `/opt/phone-use/pu/logs/` 生成三个文件：

| 文件 | 内容 |
|---|---|
| `run-<ts>.jsonl` | 完整事件轨迹：每一步工具调用与返回 |
| `run-<ts>.md` | 可读摘要：工具调用序列、关键命令、最终结论 |
| `run-<ts>.err` | 标准错误输出 |

### 4.2 原语

原语为单步动作，供任务主体调用，输出单行 JSON。

```bash
phone-hand state                        # 设备状态
phone-hand wifi                         # 当前连接信息
phone-hand probe                        # 门户拦截探测
phone-hand scan portal                  # 扫描指定关键字
phone-hand tap 540 600                  # 坐标点击
phone-hand click-text "登录"            # 按文本点击
phone-hand settext --id !account zjb    # 输入文本
phone-hand shot /sdcard/s.png           # 截图
phone-hand pull /sdcard/s.png /tmp/s.png
phone-hand wifi-connect <ssid> wpa2 <密码> --bssid <MAC>
phone-hand jar portal-login <账号> <密码>
```

完整列表见 `phone-hand --help`。

### 4.3 屏幕识别

```bash
phone-look <serial> "当前是什么页面？"
phone-look <serial> --coord "WLAN 列表中的 test-portal2"
```

输出页面与控件的文本结论；使用 `--coord` 时附带可点击坐标。

### 4.4 HTTP 接口

```bash
curl -X POST http://<host>:8902/task -H 'Content-Type: application/json' \
     -d '{"text":"连 928wpa2-psk 密码 12345678","device":"auto"}'
```

返回 `verdict`、`answer`、`serial`。`verdict` 取值：`PASS`、`FAIL`、`ANSWER`、`TIMEOUT`、`BLOCKED`。

### 4.5 新机接入

```bash
phone-doctor <serial>
```

逐项体检 USB 调试、点击能力、自动连网、电量、时间同步等；检查项与解决办法见 `docs/ONBOARD.md`。

## 5. 技能与提示词

任务主体的行为由以下文件决定：

| 文件 | 作用 |
|---|---|
| `/opt/phone-use/base/SKILL.md` | 任务手册：认证路线、成功判据、机型注意事项 |
| `/opt/phone-use/base/AGENT-PROMPT.md` | 系统提示词，安装时复制为 `/opt/phone-use/pu/.qwen/system.md` |
| `/opt/phone-use/pu/.qwen/agents/` | 子任务定义 |
| `/opt/phone-use/pu/.qwen/settings.json` | 模型、接口、记忆开关配置 |

新增机型适配写入 `/opt/phone-use/work/adapt/<机型>.yaml`。

## 6. 目录结构

```
src/      服务源码：原语、农场 API、任务入口、体检、浏览器界面
deploy/   部署文件：安装脚本、统一入口 CLI、配置、systemd 单元
tools/    辅助脚本
ops/      运维与排障脚本
docs/     使用与实现文档
legacy/   已淘汰组件
```

| 文档 | 内容 |
|---|---|
| `docs/ONBOARD.md` | 新机接入检查清单 |
| `docs/SKILL-phone-use-wlan.md` | 任务手册全文 |
| `docs/ARCHITECTURE.md` | 架构、动作后端、占用规则、已知限制 |

## 7. 常见问题

| 现象 | 处理 |
|---|---|
| `phone-use` 提示"未知命令" | 原语命令为 `phone-hand`，见 4.2 |
| 任务返回 BLOCKED | 终端被占用，用 `phone-farm status` 查看占用者或改用空闲终端 |
| 浏览器无画面 | 手机屏幕休眠，先唤屏；离线终端不显示画面 |
| 模型调用 401 | 检查 `/opt/phone-use/pu/.qwen/settings.json` 中的密钥 |
| 底层文件校验失败 | 启动器会拒绝执行，按 `docs/ARCHITECTURE.md` 第 5 节恢复 |
