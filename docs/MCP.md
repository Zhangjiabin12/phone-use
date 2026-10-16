# MCP 用法

`phone-mcp` 把手机工具面以网络 MCP 暴露，供平台 AI 与远端 agent 直接调用，无需 shell 或自行拼 HTTP。

## 1. 服务信息

| 项 | 值 |
|---|---|
| 地址 | `http://131.255.36.102:8903/mcp` |
| 传输 | `streamable-http` |
| 服务 | `phone-mcp.service`，随 `phone-farm start/stop/status/logs` 统一管理 |
| 进程 | `/opt/phone-mcp/venv/bin/python /opt/phone-mcp/phone-mcp-http.py` |

底层实现与本机 stdio 版 `phone-hub-mcp` 共用同一份代码，字段与 HTTP 接口完全一致。

## 2. 客户端接入

### 2.1 Qwen Code

```bash
# 项目级（在项目目录内执行，写入项目 .qwen/settings.json）
qwen mcp add phone-use http://131.255.36.102:8903/mcp -t http -s project --trust

# 用户级
qwen mcp add phone-use http://131.255.36.102:8903/mcp -t http -s user --trust

# 带鉴权头
qwen mcp add phone-use http://131.255.36.102:8903/mcp -t http -H "Authorization: Bearer <token>" --trust

qwen mcp list        # 查看已配置
qwen mcp remove phone-use
```

等价的 `settings.json` 配置（HTTP 型使用 `httpUrl`）：

```json
{
  "mcpServers": {
    "phone-use": {
      "httpUrl": "http://131.255.36.102:8903/mcp",
      "trust": true
    }
  }
}
```

### 2.2 其它 MCP 客户端

填写端点 URL 即可；需要指定传输类型时选 `http` 或 `streamable-http`。需要鉴权时在请求头加 `Authorization: Bearer <token>`。

## 3. 工具

| 工具 | 参数 | 返回 |
|---|---|---|
| `phone_task` | `text`（必填）、`device`（默认 `auto`）、`max_steps`、`timeout_s`（默认 600） | `verdict`、`ok`、`serial`、`delegated`、`steps`、`elapsed`、`trace`、`answer`；超时返回 `status=running` 与 `job` |
| `devices_list` | 无 | 终端清单：`serial`、`state`、`usable`、`backend`、`capabilities`、租约、阻塞项 |
| `phone_exec` | `serial`、`argv`（原语数组）、`timeout_s` | 原语返回的 JSON |
| `phone_skill` | 无 | 任务手册全文：认证路线、成功判据、机型注意事项 |
| `lease_device` | `serial`、`owner`、`ttl_s` | 占用结果；被他人持有时返回 409 |
| `release_device` | `serial`、`owner` | 释放结果 |

`verdict` 取值：`PASS` / `FAIL` / `ANSWER` / `TIMEOUT` / `BLOCKED`。

## 4. 使用示例

### 4.1 派一句话任务

```
phone_task(text="连 test-portal2 做 portal 认证，账号 zjb 密码 123456")
```

返回：

```json
{
  "ok": true, "status": "done", "verdict": "PASS",
  "serial": "463fd7bf1220", "delegated": "phone-use",
  "steps": 12, "elapsed": 96, "trace": "/opt/phone-use/pu/logs/run-<ts>.jsonl",
  "answer": "RESULT: PASS … 证据：SSID/BSSID/IP/门户返回码/外网核验/截图"
}
```

指定终端与步数上限：

```
phone_task(text="体检一下这台机器", device="57ada8", max_steps=30, timeout_s=900)
```

### 4.2 先看有哪些终端

```
devices_list()
```

只对 `usable=true` 且 `state=idle` 的终端派任务；`device="auto"` 时服务端按此规则自动选择。

### 4.3 直接跑原语

```
phone_exec(serial="57ada8", argv=["wifi"])
phone_exec(serial="CTV0221202007036", argv=["probe"])
phone_exec(serial="57ada8", argv=["tap", "540", "600"])
```

原语清单见 `phone-hand --help`。

### 4.4 独占终端

```
lease_device(serial="57ada8", owner="用例A", ttl_s=1800)
# … 期间他人申请该终端返回 409
release_device(serial="57ada8", owner="用例A")
```

只调用 `phone_task` 或 `phone_exec` 时无需显式申请，服务端会自动占用并在结束时释放。

### 4.5 长任务

`phone_task` 内部已按异步作业处理并轮询到结束。若超过 `timeout_s` 仍未结束，返回：

```json
{"ok": true, "job": "job017", "status": "running",
 "answer": "等待 600s 仍未结束；查进度 GET /tasks/job017，放弃 POST /tasks/job017/cancel"}
```

此时任务仍在后台运行，可继续查询或取消：

```bash
curl http://131.255.36.102:8902/tasks/job017
curl -X POST http://131.255.36.102:8902/tasks/job017/cancel
```

## 5. 与 HTTP 接口的关系

同一后端、同一契约，三种用法等价：

| 用法 | 入口 |
|---|---|
| MCP | `http://<host>:8903/mcp` |
| HTTP 同步 | `POST http://<host>:8902/task` |
| HTTP 异步 | `POST http://<host>:8902/tasks` → `GET /tasks/<id>` → `POST /tasks/<id>/cancel` |

字段说明与请求体格式见 `README.md` 4.4。

## 6. 鉴权

默认不鉴权。需要时在 `/opt/phone-mcp/mcp.env` 写入：

```
PHONE_MCP_TOKEN=<token>
```

重启后生效：`systemctl restart phone-mcp`。客户端需在请求头带 `Authorization: Bearer <token>`（Qwen Code 用 `qwen mcp add … -H "Authorization: Bearer <token>"`）。

## 7. 排障

| 现象 | 处理 |
|---|---|
| 连接被拒 | `phone-farm status` 看 phone-mcp 是否运行中；确认端口 8903 |
| 404 | 端点必须带路径 `/mcp` |
| 工具不出现 | 客户端的信任/审批未放行，重新以 `--trust` 添加；`qwen mcp list` 应显示该服务 |
| `verdict=BLOCKED` | 目标终端被他人占用，改 `device` 或等释放；占用者见 `devices_list` |
| `status=running` 不结束 | 任务仍在跑，用返回的 `job` 查进度或取消 |
| 任务总是超时 | 提高 `timeout_s`；或先用 `devices_list` 确认终端 `usable=true` |
