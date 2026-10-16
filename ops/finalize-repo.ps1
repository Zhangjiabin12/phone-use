Set-Location "E:\dsh_project\远程桌面 36.102"
$ErrorActionPreference='Continue'

# ---- 1) install-all.sh：对齐新目录布局（上传到 /tmp 的名字也统一）----
$p='deploy\install-all.sh'; $t=Get-Content -Raw -LiteralPath $p
$t = $t.Replace('cp -f /tmp/phone-use-v4.py     /usr/local/share/phone-use/phone-use.py','cp -f /tmp/phone-use.py         /usr/local/share/phone-use/phone-use.py')
$t = $t.Replace('cp -f /tmp/phone-wall-svc.py   /usr/local/share/phone-wall/phone-wall.py','cp -f /tmp/phone-wall.py        /usr/local/share/phone-wall/phone-wall.py')
if ($t -notmatch 'phone-farm') {
  $t = $t.Replace('for u in phone-hub phone-agent phone-wall; do cp -f /tmp/$u.service /etc/systemd/system/$u.service; done',
@'
for u in phone-hub phone-agent phone-wall; do cp -f /tmp/$u.service /etc/systemd/system/$u.service; done

# 统一入口 phone-farm（单一配置 + 启停/状态/日志）
mkdir -p /usr/local/share/phone-farm
[ -f /tmp/farm.env ] && cp -f /tmp/farm.env /usr/local/share/phone-farm/farm.env
[ -f /tmp/phone-farm ] && install -m 755 /tmp/phone-farm /usr/local/bin/phone-farm
for u in phone-hub phone-agent phone-wall; do
  f=/etc/systemd/system/$u.service
  grep -q 'phone-farm/farm.env' $f || sed -i 's#^\[Service\]#[Service]\nEnvironmentFile=-/usr/local/share/phone-farm/farm.env#' $f
done
'@)
}
$header = @'
#!/bin/bash
# 幂等部署：把仓库里的文件装到主机（systemd 单元 + 服务代码 + 统一入口）
# 在仓库根目录执行：
#   scp src/*.py src/wall/* deploy/*.env deploy/phone-farm deploy/units/*.service \
#       docs/SKILL-phone-use-wlan.md docs/ONBOARD.md tools/pu-node.py root@<host>:/tmp/
#   ssh root@<host> bash /tmp/install-all.sh
'@
if ($t -notmatch '在仓库根目录执行') { $t = $header + "`n" + ($t -replace '(?m)^#!.*\r?\n','') }
Set-Content -LiteralPath $p -Value $t -NoNewline -Encoding UTF8
"install-all.sh 已对齐: $($t -match 'tmp/phone-wall.py') / 含 phone-farm: $($t -match 'install -m 755 /tmp/phone-farm')"

# ---- 2) README：目录结构与快速开始改成新布局 ----
$r='README.md'; $k=Get-Content -Raw -LiteralPath $r
$oldStart = $k.IndexOf('```' + "`nphone-use.py")
if ($oldStart -gt 0) {
  $oldEnd = $k.IndexOf('```', $oldStart+3)
  $newTree = @'
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
├── ops/                          # 运维脚本（代理 mihomo、ws-scrcpy 高清流、端口清理…）
├── docs/                         # 文档与截图
│   ├── ONBOARD.md                #   新机接入清单（10 步 + 六类坑）
│   ├── SKILL-phone-use-wlan.md   #   给 agent 的 runbook（8901 /skill 供出）
│   └── img/                      #   实测证据截图
└── legacy/                       # 已淘汰组件（旧单机投屏等）
```
'@
  $k = $k.Substring(0,$oldStart) + $newTree + $k.Substring($oldEnd+3)
}
$k = $k.Replace('scp *.py *.html *.env *.service install-all.sh build-pu-jar.sh root@<host>:/tmp/',
                'scp src/*.py src/wall/* deploy/*.env deploy/phone-farm deploy/units/*.service docs/*.md tools/pu-node.py root@<host>:/tmp/')
$k = $k.Replace('# 2) 部署（幂等，可重复跑）','# 2) 部署（幂等，可重复跑；配置只改 deploy/farm.env）')
$k = $k.Replace('open http://<host>:8910/','phone-farm status            # 统一看服务/端口/终端/墙地址')
$k = $k.Replace('# 5) 一句话下单','# 5) 一句话下单（或直接在手机墙上输入）')
Set-Content -LiteralPath $r -Value $k -NoNewline -Encoding UTF8
"README 已更新结构: $($k -match 'deploy/phone-farm')"

# ---- 3) LICENSE ----
if (-not (Test-Path LICENSE)) {
  $lic = @'
MIT License

Copyright (c) 2026 Zhangjiabin12

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
'@
  Set-Content -LiteralPath LICENSE -Value $lic -NoNewline -Encoding UTF8
  "LICENSE 已加（MIT）"
}

# ---- 4) 提交推送 ----
if (Test-Path .git\index.lock) { Remove-Item -Force .git\index.lock }
git add -A 2>&1 | Where-Object { $_ -notmatch 'LF will be replaced' } | Select-Object -First 2
git commit -q -m "refactor: 目录结构重组（src/ deploy/ tools/ docs/ ops/ legacy/）+ 统一部署脚本路径 + MIT LICENSE" 2>&1 | Select-Object -First 2
git push -q origin main 2>&1 | Select-Object -Last 2
"== 提交历史 =="; git log --oneline -3
"== 仓库根目录 =="; git ls-files | ForEach-Object { ($_ -split '/')[0] } | Group-Object | Sort-Object Count -Descending | ForEach-Object { "  $($_.Name) : $($_.Count)" }