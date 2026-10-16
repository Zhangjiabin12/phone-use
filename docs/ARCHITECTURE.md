# 架构与实现说明

本文档描述 phone-use 的当前实现，供部署、维护与排障使用。使用方法见 `README.md`。

## 1. 组件与端口

| 端口 | 服务 | 作用 | 使用者 |
|---|---|---|---|
| 8910 | `phone-wall` | 浏览器界面：画面、按键、派任务、体检、占用管理 | 人 |
| 8902 | `phone-agent` | 一句话任务接口；将任务转交任务主体执行 | 人、平台 |
| 8901 | `phone-hub` | 终端清单、能力集、版本、占用闸、体检接口、原语执行接口 | 程序 |
| 8000 | `ws-scrcpy` | 画面视频流，由 8910 内嵌 | 仅 8910 |

调用关系：

```
人 ───► 8910 phone-wall ─┐
                         ├──► 8902 phone-agent ──► phone-use（任务主体：Qwen Code）
平台 ─► 8902 /task ──────┘                                  │
                                                           ▼
                                               phone-hand 原语 / phone-look
                                                           │
                                                           ▼
                                              8901 phone-hub ──► adb ──► 真机
```

## 2. 任务主体与执行环境

| 项 | 说明 |
|---|---|
| 任务主体 | Qwen Code，以系统用户 `phonebot` 运行 |
| 权限 | `phonebot` 无 sudo、无 root；底层目录对非 root 为只读 |
| 工作目录 | `/opt/phone-use/pu`，项目级配置在该目录的 `.qwen/` 下 |
| 任务入口 | `/usr/local/bin/phone-use`；每次运行保存轨迹，见 README 4.1 |
| 接口接入 | 项目级 `settings.json` 的 `env` 配置模型与密钥，`mcpServers` 接入 `phone-hub` |
| 视觉 | 主模型直接读图；模型能力表缺失时用 `ops/fix-vision-registry.sh` 补齐 |

## 3. 动作后端与回退

原语按优先级自动选择动作后端，无需人工指定：

| 优先级 | 后端 | 条件 | 能力 |
|---|---|---|---|
| P1 | `root-input` | 设备有 root | 坐标手势、按键、输入注入 |
| P2 | `input` | 系统允许 `adb shell input` | 坐标手势、按键、输入注入 |
| P3 | `jar-node-action` | 免 root 机型 | 无障碍节点动作：文本/描述/ID 点击、输入、滚动、返回等；不支持任意坐标 |

回退由原语内部完成；`phone-hub` 的 `backend` 字段给出实际选中的后端。

设备能力集 `capabilities` 取值：

```
read-ui  screenshot  shell  node-click  settext  scroll  global-action  http-from-phone
join-open  join-psk  lock-bssid  mac-policy  portal-ui  1x-ui
su  supplicant-config  input-inject  coordinate-gesture  keyevent  install-apk
```

## 4. 占用规则

| 项 | 规则 |
|---|---|
| 租约 | 同一终端同一时刻只允许一个持有者；他人持有效租约时申请返回 409 |
| 自动占用 | `phone_exec` 等执行接口会自动申请并释放租约，调用方无需先显式申请 |
| 心跳 | 心跳不视为设备活动；`last_activity` 仅由实际执行刷新 |
| 停滞回收 | 持租约但长期无活动时自动回收 |
| 离线清理 | 离线超过 `OFFLINE_PRUNE`（默认 86400 秒）的终端从清单剔除 |
| 选机 | 任务默认选择 `usable=true` 且 `stf_state=available` 的终端 |

`usable` 由以下条件决定：终端在线、动作后端可用、可执行 `cmd wifi connect-network`。
不满足自动连网条件的终端标记为 `usable=false`，其原因是无法无人值守完成连网类任务。

## 5. 文件布局与冻结

```
/opt/phone-use/base/            底层，root 属主，a-w，只读
  phone-hand.py                 原语实现
  phone-look                    屏幕识别
  SKILL.md                      任务手册
  ONBOARD.md                    接入检查清单
  AGENT-PROMPT.md               系统提示词源文件
/opt/phone-use/base.sha256      上述文件校验清单
/opt/phone-use/work/            工作区，任务主体可写
  copies/                       改动的副本
  adapt/                        机型适配
  notes/                        记录
/opt/phone-use/pu/              任务主体项目目录
  .qwen/                        项目级配置
  logs/                         运行轨迹
/usr/local/bin/phone-use        任务入口，读取 base 并做校验
/usr/local/bin/phone-hand       原语入口，读取 base 并做校验
/usr/local/bin/phone-look       屏幕识别入口
```

修改底层文件的流程：

```bash
cp /opt/phone-use/base/<文件> /opt/phone-use/work/copies/<文件>.<时间戳>
# 修改副本并验证
cp /opt/phone-use/work/copies/<文件>.<时间戳> /opt/phone-use/base/<文件>
cd /opt/phone-use/base && sha256sum * > /opt/phone-use/base.sha256
```

校验失败时：执行入口会返回退出码 90 并拒绝运行。恢复方式为将 `base` 内容还原为清单对应版本后重算 `base.sha256`；`base.sha256` 的备份位于工作区 `copies/`。

## 6. 项目级配置项

`/opt/phone-use/pu/.qwen/settings.json`：

| 键 | 说明 |
|---|---|
| `env.OPENAI_API_KEY` | 接口密钥 |
| `env.OPENAI_BASE_URL` | 接口地址 |
| `env.OPENAI_MODEL` | 模型名 |
| `mcpServers.phone-hub` | 接入本地农场接口的 MCP 服务 |
| `model.visionModel` | 图像识别所用模型 |
| `memory.*` | 自动记忆与自动技能开关 |

## 7. 已知限制

| 限制 | 说明 |
|---|---|
| 免 root 机型无任意坐标点击 | 仅支持无障碍节点动作；坐标手势需 root 或系统允许 `input` |
| 部分机型不支持命令式连网 | 此类终端不可无人值守连网，标记 `usable=false` |
| 屏幕识别速度 | 单次识别随图像大小与模型响应变化 |
| 视频流端口 | `ws-scrcpy` 固定使用 8000，不支持改端口 |
