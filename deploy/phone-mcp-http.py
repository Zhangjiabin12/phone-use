#!/usr/bin/env python3
"""phone-mcp —— 把手机工具面以网络 MCP 暴露（streamable-http）。

工具与 stdio 版 phone-hub-mcp 一致：devices_list / phone_exec / phone_task /
phone_skill / lease_device / release_device。实现复用同一份代码，避免两套逻辑。
可选鉴权：环境变量 PHONE_MCP_TOKEN 非空时，要求请求带 Authorization: Bearer <token>。
"""
import importlib.util
import os

from fastmcp import FastMCP

HUB_MCP = os.environ.get("PHONE_HUB_MCP", "/usr/local/share/phone-hub/phone-hub-mcp.py")
spec = importlib.util.spec_from_file_location("hub_mcp", HUB_MCP)
hub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hub)          # 该模块仅在 __main__ 下才起 stdio 循环

mcp = FastMCP("phone-use")


@mcp.tool
def devices_list() -> dict:
    """列出手机终端：serial、状态、可用性(usable)、后端、能力集、占用情况。"""
    return hub.call_tool("devices_list", {})


@mcp.tool
def phone_task(text: str, device: str = "auto", max_steps: int | None = None,
               timeout_s: int = 600) -> dict:
    """给一句话任务（连网/认证/取证等）。返回 verdict(PASS/FAIL/ANSWER/TIMEOUT/BLOCKED)、
    serial、steps、elapsed、trace 与答复原文；超时返回 job 号供继续查询。"""
    args = {"text": text, "device": device, "timeout_s": timeout_s}
    if max_steps:
        args["max_steps"] = max_steps
    return hub.call_tool("phone_task", args)


@mcp.tool
def phone_exec(serial: str, argv: list[str], timeout_s: int = 600) -> dict:
    """在指定终端执行一条原语，例如 argv=["wifi"]、["probe"]、["tap","540","600"]。"""
    return hub.call_tool("phone_exec", {"serial": serial, "argv": argv, "timeout_s": timeout_s})


@mcp.tool
def phone_skill() -> dict:
    """取任务手册（认证路线、成功判据、机型注意事项）。"""
    return hub.call_tool("phone_skill", {})


@mcp.tool
def lease_device(serial: str, owner: str, ttl_s: int = 1800) -> dict:
    """独占一台终端。被他人持有时返回 409。"""
    return hub.call_tool("lease_device", {"serial": serial, "owner": owner, "ttl": ttl_s})


@mcp.tool
def release_device(serial: str, owner: str) -> dict:
    """释放终端。"""
    return hub.call_tool("release_device", {"serial": serial, "owner": owner})


if __name__ == "__main__":
    host = os.environ.get("PHONE_MCP_HOST", "0.0.0.0")
    port = int(os.environ.get("PHONE_MCP_PORT", "8903"))
    mcp.run(transport="streamable-http", host=host, port=port)
