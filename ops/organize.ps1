# 整理仓库结构：源码在根，运维脚本进 ops/，淘汰件进 legacy/，图片进 docs/img/
Set-Location "E:\dsh_project\远程桌面 36.102"
$ErrorActionPreference = 'SilentlyContinue'
New-Item -ItemType Directory -Force -Path ops, legacy, docs\img | Out-Null

# 1) 源码命名统一：部署用的 phone-use-v4.py 就是正式版，落成 phone-use.py
if (Test-Path 'phone-use-v4.py') {
  Move-Item -Force 'phone-use.py' 'legacy\phone-use-v1.py'
  Move-Item -Force 'phone-use-v4.py' 'phone-use.py'
}
Move-Item -Force 'phone-view.py' 'legacy\phone-view.py'
Move-Item -Force 'deploy-phone-view2.sh' 'legacy\deploy-phone-view2.sh'

# 2) 运维脚本（代理 / ws-scrcpy / 清理 / 部署辅助）
$ops = @('install-mihomo.sh','mihomo-mmdb.sh','fix-mihomo.sh','fix-mihomo2.sh','fix-mihomo3.sh',
         'mirror-mihomo.sh','diag-mihomo.sh','diag-mihomo2.sh','ws-node16.sh','ws-scrcpy-svc.sh',
         'build-ws.sh','check-ws.sh','finish-scrcpy.sh','ports-and-cleanup.sh','agent-uses-hub.sh',
         'deploy-all.sh','deploy-fixes.sh','deploy-skill-scrcpy.sh','deploy-usable-rule.sh')
foreach ($f in $ops) { if (Test-Path $f) { Move-Item -Force $f "ops\$f" } }

# 3) 华为现场排查脚本 + 修页面脚本（保留作证据）
foreach ($f in @('hw-portal.sh','hw-portal-proto.sh','embed-stream.ps1','fix-keybar.py')) {
  if (Test-Path $f) { Move-Item -Force $f "ops\$f" }
}
# 纯临时/重复的删掉
foreach ($f in @('uhid-up.sh','jump-socks.mjs')) { if (Test-Path $f) { Remove-Item -Force $f } }

# 4) 图片证据进 docs/img
Get-ChildItem -File -Include *.png,*.jpg,*.jpeg | ForEach-Object { Move-Item -Force $_.FullName "docs\img\" }

# 5) 看最终结构
"== 根目录 =="
Get-ChildItem | Select-Object Mode,Name | Format-Table -AutoSize | Out-String -Width 40
"== 子目录文件数 =="
foreach ($d in 'ops','legacy','docs\img','pu-jar') { if (Test-Path $d) { "  $d : $((Get-ChildItem -Recurse -File $d).Count) 个" } else { "  $d : (不存在)" } }
