# ops/ —— 运维与现场排查脚本

这些脚本**不是**农场运行必需的，是搭建/排障/取证时用的。按用途分组：

## 出网代理（mihomo）
| 脚本 | 用途 |
|---|---|
| `install-mihomo.sh` | 装 mihomo（Clash.Meta）到 /usr/local/bin + systemd 单元 + 拉订阅 |
| `mihomo-mmdb.sh` | **最终可用版**：用本地 GeoLite2-Country.mmdb + 精简规则（只留 proxies/proxy-groups/GEOIP + MATCH），去掉一切需要联网下载的东西 |
| `fix-mihomo.sh` / `fix-mihomo2.sh` / `fix-mihomo3.sh` | 排障三步（GeoIP 下载失败导致崩溃重启 102 次的定位过程，保留作证据） |
| `diag-mihomo.sh` / `diag-mihomo2.sh` | 诊断：单元状态、配置自检、监听端口、MMDB 载入 |
| `mirror-mihomo.sh` | 从国内镜像拉二进制（GitHub release 直连被卡时用） |

## 高清画面（ws-scrcpy）
| 脚本 | 用途 |
|---|---|
| `ws-node16.sh` | **最终可用版**：便携 Node16（/opt/node16，不动系统 Node18）构建 ws-scrcpy 并起服务 |
| `build-ws.sh` / `check-ws.sh` / `finish-scrcpy.sh` | 构建/检查/补装（中途版本） |
| `ws-scrcpy-svc.sh` | 早期 systemd 单元版本 |

## 现场排查与取证
| 脚本 | 用途 |
|---|---|
| `hw-portal.sh` / `hw-portal-proto.sh` | 华为 nova 9 门户认证：界面式（失败）与协议式（成功）对照实验 |
| `agent-uses-hub.sh` | 验证 agent 是否通过 8901 判"哪些终端能用"（拉代码 + 现场数据） |
| `ports-and-cleanup.sh` | 端口归位（ws-scrcpy→89xx 段）+ 清理旧服务 + 逐端口探活 |
| `embed-stream.ps1` / `fix-keybar.py` | 把 H.264 流嵌进手机墙卡片、修复按键条（页面改造时用） |
| `deploy-*.sh` | 各阶段的一次性部署脚本（含 deploy-all / deploy-fixes 等） |

> 约定：**运行必需的只有仓库根的 `src/` + `deploy/`**；`ops/` 里的东西照做能复现当时的搭建与排障过程。