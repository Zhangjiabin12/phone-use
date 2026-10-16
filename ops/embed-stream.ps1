$ErrorActionPreference='Continue'
Set-Location "E:\dsh_project\远程桌面 36.102"
$p = "wall-page.html"
$t = Get-Content -Raw -LiteralPath $p

# 1) CSS：iframe 样式
if ($t -notmatch '\.screenframe\{') {
  $t = $t.Replace(".keybar{display:flex", ".screenframe{width:100%;min-height:520px;border:0;border-radius:var(--radius-sm);background:#000;display:block}`n.keybar{display:flex")
}

# 2) 卡片的屏幕区：把 MJPEG <img> 换成 ws-scrcpy 的 H.264 iframe
$oldImg = @'
    <div class="screen-wrap"><img class="screen" src="/screen/${dev.serial}" alt="${esc(dev.model)} 实时画面">
      <div class="screen-overlay" style="display:none"></div></div>
'@
$newIfr = @'
    <div class="screen-wrap">${frameTag(dev)}
      <div class="screen-overlay" style="display:none"></div></div>
'@
if ($t.Contains($oldImg)) { $t = $t.Replace($oldImg, $newIfr) } else { Write-Host "  [warn] 屏幕区锚点未匹配" }

# 3) 生成 iframe 的函数（用当前访问的主机名 + 8920）
$fn = @'
// 高清画面：把 ws-scrcpy 的 H.264 流直接嵌进卡片（不再用低帧率截图流）
const SCRCPY_PORT = 8920;
function frameTag(dev){
  const H = location.hostname;
  const ws = encodeURIComponent(`ws://${H}:${SCRCPY_PORT}/?action=proxy-adb&remote=tcp%3A8886&udid=${dev.serial}`);
  const src = `http://${H}:${SCRCPY_PORT}/#!action=stream&udid=${dev.serial}&player=mse&ws=${ws}&fitToScreen=true`;
  return `<iframe class="screenframe" src="${src}" allow="autoplay; fullscreen" loading="lazy"
            title="${esc(dev.model||dev.serial)} 实时画面（H.264）"></iframe>`;
}
'@
$t = $t.Replace("const LAST={};", $fn + "`nconst LAST={};")

# 4) updateCard 里的 img 逻辑加空值保护（现在没有 <img> 了）
$t = $t.Replace("const ov=c.querySelector('.screen-overlay'), img=c.querySelector('.screen');",
                "const ov=c.querySelector('.screen-overlay'), img=c.querySelector('.screen');`n  if(!img){ov.style.display='none';return;}")
$t = $t.Replace("const img=ev.target,r=img.getBoundingClientRect();",
                "const img=ev.target,r=img.getBoundingClientRect();`n  if(ev.target.tagName!=='IMG')return;")
Set-Content -LiteralPath $p -Value $t -NoNewline -Encoding UTF8
Write-Host ("  frameTag 函数: " + ($t -match 'function frameTag'))
Write-Host ("  iframe 调用:   " + ($t -match '\$\{frameTag\(dev\)\}'))
Write-Host ("  空值保护:      " + ($t -match 'if\(!img\)'))

scp -o BatchMode=yes $p root@131.255.36.102:/usr/local/share/phone-wall/wall-page.html 2>&1 | Out-Null
