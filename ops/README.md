# ops/ —— 运维与现场排查脚本

这些脚本**不是**农场运行必需的，是搭建/排障/取证时用的。按用途分组：

## 高清画面（ws-scrcpy）
| 脚本 | 用途 |
|---|---|
| `ws-node16.sh` | **最终可用版**：便携 Node16（/opt/node16，不动系统 Node18）构建 ws-scrcpy 并起服务 |
| `build-ws.sh` / `check-ws.sh` / `finish-scrcpy.sh` | 构建 / 检查 / 补装（中途版本） |
| `ws-scrcpy-svc.sh` | 早期 systemd 单元版本 |

## 现场排查与取证
| 脚本 | 用途 |
|---|---|
| `hw-portal.sh` / `hw-portal-proto.sh` | 华为 nova 9 门户认证：界面式（失败）与协议式（成功）对照实验 |
| `agent-uses-hub.sh` | 验证 agent 是否通过 8901 判"哪些终端能用" |
| `ports-and-cleanup.sh` | 端口归位 + 清理旧服务 + 逐端口探活 |
| `embed-stream.ps1` / `fix-keybar.py` | 把 H.264 流嵌进手机墙卡片、修复按键条 |
| `deploy-*.sh` | 各阶段一次性部署脚本 |

> **不在本目录**：出网代理（mihomo/Clash）相关脚本已从仓库移除 —— 那是**环境基建**，且含订阅凭据，
> 不该出现在项目里。农场本身不依赖它，只需要环境能出网/能访问 adb。