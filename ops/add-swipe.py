import ast
import re

# ---------- 1) 后端：加 /api/swipe（照 /api/click 的写法）----------
p = '/usr/local/share/phone-wall/phone-wall.py'
s = open(p, encoding='utf-8').read()
if '/api/swipe' in s:
    print("  后端已有 /api/swipe")
else:
    m = re.search(r'            if p == "/api/click":\n(.*?)\n            if p == "/api/task":', s, re.S)
    assert m, "找不到 /api/click 块"
    block = m.group(0)
    swipe = block.replace('/api/click', '/api/swipe')
    # 改成 swipe 原语
    swipe = swipe.replace(
        'argv = ["tap", str(body["x"]), str(body["y"])] if dev.get("root") \\\n                    else ["click-xy", str(body["x"]), str(body["y"])]',
        'argv = ["swipe", str(body["x1"]), str(body["y1"]), str(body["x2"]), str(body["y2"]),\n                        str(body.get("ms", 300))]')
    s = s.replace(block, block + swipe, 1)
    open(p, 'w', encoding='utf-8').write(s)
    ast.parse(s)
    print("  后端已加 /api/swipe（swipe x1 y1 x2 y2 ms）")

# ---------- 2) 前端：卡片画面支持拖拽 = swipe ----------
q = '/usr/local/share/phone-wall/wall-page.html'
h = open(q, encoding='utf-8').read()
if 'id="v12"' not in h:
    blk = r'''<script id="v12">
(function(){
  var drag = null, lastDrag = 0;
  function api(path, body){
    return fetch(path, {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body)}).then(r=>r.json()).catch(()=>null);
  }
  function serialOf(el){
    var img = el.closest('.phone') && el.closest('.phone').querySelector('img.screen');
    if (!img) return '';
    var m = /\/screen\/([^\/?#]+)/.exec(img.getAttribute('src') || img.src || '');
    return m ? decodeURIComponent(m[1]) : '';
  }
  function scale(el){
    var img = el.closest('.phone') && el.closest('.phone').querySelector('img.screen');
    if (!img) return null;
    var r = img.getBoundingClientRect();
    var d = (window.S && S.devices ? S.devices : []).find(x => serialOf(el) === x.serial) || {};
    var w = d.screen_w || 1080, hh = d.screen_h || 2340;
    return {oy: hh / r.height, ox: w / r.width, rect: r};
  }
  document.addEventListener('pointerdown', function(ev){
    var phone = ev.target.closest('.phone');
    if (!phone || ev.target.closest('iframe')) return;
    var sc = scale(phone); if (!sc) return;
    drag = {phone: phone, x0: ev.clientX, y0: ev.clientY, moved: false};
  }, true);
  document.addEventListener('pointerup', function(ev){
    if (!drag) return;
    var dx = ev.clientX - drag.x0, dy = ev.clientY - drag.y0;
    var d = Math.hypot(dx, dy);
    var phone = drag.phone;
    var track = drag; drag = null;
    if (d < 12) return;                       // 小位移交给原生 click
    var sc = scale(phone); if (!sc) return;
    var serial = serialOf(phone); if (!serial) return;
    var r = sc.rect;
    var x1 = Math.round((track.x0 - r.left) * sc.ox), y1 = Math.round((track.y0 - r.top) * sc.oy);
    var x2 = Math.round((ev.clientX - r.left) * sc.ox), y2 = Math.round((ev.clientY - r.top) * sc.oy);
    lastDrag = Date.now();
    api('/api/swipe', {serial: serial, x1: x1, y1: y1, x2: x2, y2: y2, ms: 260});
  }, true);
  /* 拖拽结束后 300ms 内吃掉合成 click，避免"滑动变点击" */
  document.addEventListener('click', function(ev){
    if (Date.now() - lastDrag < 320) { ev.stopPropagation(); ev.preventDefault(); }
  }, true);
})();
</script>'''
    h = h.replace('</body>', blk + '\n</body>')
    open(q, 'w', encoding='utf-8').write(h)
    print("  前端已加拖拽→swipe（并抑制滑动后的误点击）")
else:
    print("  前端已有 v12")
