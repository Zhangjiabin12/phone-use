import re

p = '/usr/local/share/phone-wall/wall-page.html'
s = open(p, encoding='utf-8').read()

# 1) 移除上一版「每张卡片都插 iframe」的 v10 块（script + style）
a = s.find('<script id="v10">')
b = s.find('</style>', s.find('<style id="v10s">')) 
if a >= 0 and b > a:
    s = s[:a] + s[b + len('</style>'):]
    print("  已移除 v10（每卡 iframe）")

# 2) 追加 v11：只在大屏里开一路实时流
if 'id="v11"' not in s:
    blk = '''<script id="v11">
(function(){
  var PORT = 8000;
  function serialOf(img){
    var m = /\\/screen\\/([^\\/?#]+)/.exec(img.getAttribute('src') || img.src || '');
    return m ? decodeURIComponent(m[1]) : '';
  }
  function streamURL(serial, big){
    var base = location.hostname || '131.255.36.102';
    var ws = encodeURIComponent('ws://' + base + ':' + PORT + '/?action=proxy-adb&remote=tcp%3A8886&udid=' + serial);
    var q = big ? '&bitrate=8000000&maxSize=1280' : '&bitrate=3000000&maxSize=720';
    return 'http://' + base + ':' + PORT + '/#!action=stream&udid=' + encodeURIComponent(serial) +
           '&player=mse&ws=' + ws + '&fitToScreen=true' + q;
  }
  function live(col, serial){
    if (col.querySelector('iframe.screenframe')) return;
    var img = col.querySelector('img.screen'); if (!img) return;
    var f = document.createElement('iframe');
    f.className = 'screenframe';
    f.src = streamURL(serial, true);
    f.setAttribute('allow', 'autoplay; fullscreen');
    f.title = serial;
    f.style.cssText = 'width:100%;height:100%;border:0;border-radius:inherit;display:block;background:#000';
    img.style.display = 'none';
    img.parentElement.insertBefore(f, img);
  }
  function dead(col){
    var f = col.querySelector('iframe.screenframe');
    if (!f) return;
    f.remove();
    var img = col.querySelector('img.screen'); if (img) img.style.display = '';
  }
  function scan(){
    document.querySelectorAll('.phone-col').forEach(function(col){
      var inCard = !!col.closest('.card');
      var img = col.querySelector('img.screen');
      if (!inCard && img) live(col, serialOf(img));   // 大屏：开一路实时流
      else if (inCard) dead(col);                      // 卡片：不留流
    });
  }
  scan();
  setInterval(scan, 600);
})();
</script>
<style id="v11s">
img.screen{display:block}
</style>'''
    s = s.replace('</body>', blk + '\n</body>')
    print("  已注入 v11（仅大屏一路实时流）")
open(p, 'w', encoding='utf-8').write(s)
print("  落盘完成，大小 %.1f KB" % (len(s) / 1024))
