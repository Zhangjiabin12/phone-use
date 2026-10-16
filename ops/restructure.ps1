Set-Location "E:\dsh_project\远程桌面 36.102"
$ErrorActionPreference='Continue'
# 目录骨架
foreach ($d in 'src','src/wall','src/jar','deploy','deploy/units','tools','docs') { New-Item -ItemType Directory -Force -Path $d | Out-Null }

# 用 git mv 保留历史：代码 / 部署 / 工具 / 文档 各归其位
function MV($from,$to){ if (Test-Path $from) { git mv -f $from $to 2>&1 | Out-Null; if (Test-Path $from) { Move-Item -Force $from $to } } }

# --- 源码 ---
MV 'phone-use.py'        'src/phone-use.py'
MV 'phone-hub.py'        'src/phone-hub.py'
MV 'phone-hub-mcp.py'    'src/phone-hub-mcp.py'
MV 'phone-agent.py'      'src/phone-agent.py'
MV 'phone-doctor.py'     'src/phone-doctor.py'
MV 'phone-wall-svc.py'   'src/wall/phone-wall.py'
MV 'wall-page.html'      'src/wall/wall-page.html'
# --- jar ---
MV 'build-pu-jar.sh'     'src/jar/build-pu-jar.sh'
if (Test-Path 'pu-jar') { git mv -f 'pu-jar' 'src/jar/src' 2>&1 | Out-Null; if (Test-Path 'pu-jar') { Move-Item -Force 'pu-jar' 'src/jar/src' } }
# --- 部署 ---
foreach ($f in 'install-all.sh','install-phone-farm.sh') { MV $f "deploy/$f" }
foreach ($f in 'farm.env','hub.env','agent.env') { MV $f "deploy/$f" }
MV 'phone-farm'          'deploy/phone-farm'
Get-ChildItem -File -Filter *.service | ForEach-Object { MV $_.Name "deploy/units/$($_.Name)" }
# --- 工具 ---
MV 'pu-node.py'          'tools/pu-node.py'
MV 'pu-find.py'          'tools/pu-find.py'
# --- 文档 ---
MV 'ONBOARD.md'          'docs/ONBOARD.md'
MV 'SKILL-phone-use-wlan.md' 'docs/SKILL-phone-use-wlan.md'

# ops 里的安装脚本改名对齐
if (Test-Path 'ops/install-phone-farm.sh') { git mv -f 'ops/install-phone-farm.sh' 'deploy/install-phone-farm.sh' 2>&1 | Out-Null }

"== 新结构 =="
git status --short | Select-Object -First 40
"== 根目录剩下 =="
Get-ChildItem | Select-Object -ExpandProperty Name