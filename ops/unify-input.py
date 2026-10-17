import re

p = '/usr/local/share/phone-wall/wall-page.html'
s = open(p, encoding='utf-8').read()

if 'id="v13"' in s:
    print("已有 v13")
else:
    blk = r'''<script id="v13">
/* 统一输入：不看机型，点击→/api/click，拖拽→/api/swipe；自己算坐标并阻止页面旧处理器重复触发 */
(function(){
  var move = null, suppressUntil = 0;
  function post(path, body){
    return fetch(path, {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body)}).catch(function(){});
  }
  function ctx(el){
    var phone = el.closest('.phone'); if (!phone) return null;
    var img = phone.querySelector('img.screen'); if (!img) return null;
    var r = img.getBoundingClientRect(); if (!r.width || !r.height) return null;
    var m = /\/screen\/([^\/?#]+)/.exec(img.getAttribute('src') || img.src || '');
    var serial = m ? decodeURIComponent(m[1]) : '';
    if (!serial) return null;
    var d = ((window.S && S.devices) ? S.devices : []).find(function(x){ return x.serial === serial; }) || {};
    return {phone: phone, rect: r, serial: serial,
            w: d.screen_w || 1080, h: d.screen_h || 2340};
  }
  function toDevice(c, cx, cy){
    var x = Math.round((cx - c.rect.left) * c.w / c.rect.width);
    var y = Math.round((cy - c.rect.top) * c.h / c.rect.height);
    x = Math.max(0, Math.min(c.w - 1, x));
    y = Math.max(0, Math.min(c.h - 1, y));
    return [x, y];
  }
  document.addEventListener('pointerdown', function(ev){
    if (ev.target.closest('iframe')) return;              /* 大屏里的 ws-scrcpy 自己处理 */
    var c = ctx(ev.target); if (!c) return;
    move = {c: c, x0: ev.clientX, y0: ev.clientY};
  }, true);
  document.addEventListener('pointerup', function(ev){
    if (!move) return;
    var st = move; move = null;
    var dx = ev.clientX - st.x0, dy = ev.clientY - st.y0;
    var far = Math.hypot(dx, dy) >= 12;
    var p1 = toDevice(st.c, st.x0, st.y0);
    if (far) {
      var p2 = toDevice(st.c, ev.clientX, ev.clientY);
      post('/api/swipe', {serial: st.c.serial, x1: p1[0], y1: p1[1], x2: p2[0], y2: p2[1], ms: 260});
    } else {
      post('/api/click', {serial: st.c.serial, x: p1[0], y: p1[1]});
    }
    suppressUntil = Date.now() + 400;                     /* 阻止页面旧 click 处理器再发一次 */
  }, true);
  document.addEventListener('click', function(ev){
    if (Date.now() < suppressUntil) { ev.stopPropagation(); ev.preventDefault(); }
  }, true);
})();
</script>'''
    s = s.replace('</body>', blk + '\n</body>')
    open(p, 'w', encoding='utf-8').write(s)
    print("已注入 v13：统一点击/拖拽驱动")
