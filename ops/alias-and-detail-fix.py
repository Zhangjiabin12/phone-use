import ast
import re

WALL = '/usr/local/share/phone-wall/phone-wall.py'
PAGE = '/usr/local/share/phone-wall/wall-page.html'
ALIAS = '/usr/local/share/phone-wall/aliases.json'

# ---------------- 1) 后端：别名存储 + /api/alias + /api/devices 合并 ----------------
s = open(WALL, encoding='utf-8').read()
if '/api/alias' in s:
    print("  后端已有 alias")
else:
    # 1.1 顶部加载别名
    anchor = 'FRAME_CACHE, WALL_LOOPS, LOCK = {}, {}, threading.Lock()'
    assert anchor in s, "锚点未找到"
    s = s.replace(anchor, anchor + '''
ALIAS_FILE = "%s"
try:
    ALIASES = json.load(open(ALIAS_FILE, encoding="utf-8"))
except Exception:
    ALIASES = {}


def _save_aliases():
    try:
        with open(ALIAS_FILE, "w", encoding="utf-8") as _f:
            json.dump(ALIASES, _f, ensure_ascii=False, indent=2)
    except Exception:
        pass
''' % ALIAS, 1)

    # 1.2 /api/devices 里注入 alias
    s = s.replace('dev["screen_blank"] = bool(item[2]) if item else None',
                  'dev["screen_blank"] = bool(item[2]) if item else None\n                        dev["alias"] = ALIASES.get(dev.get("serial"))')

    # 1.3 新增 /api/alias 路由（放在 /api/click 之前）
    route = '''            if p == "/api/alias":
                name = (body.get("name") or "").strip()[:40]
                if name:
                    ALIASES[serial] = name
                else:
                    ALIASES.pop(serial, None)
                _save_aliases()
                return self._send({"serial": serial, "alias": ALIASES.get(serial)})
'''
    s = s.replace('            if p == "/api/click":', route + '            if p == "/api/click":', 1)
    open(WALL, 'w', encoding='utf-8').write(s)
    ast.parse(s)
    print("  后端已加 /api/alias 与 alias 注入")

# ---------------- 2) 前端：替换 v15，修正取数并加命名 ----------------
h = open(PAGE, encoding='utf-8').read()
a = h.find('<script id="v15">')
b = h.find('</script>', a)
if a >= 0 and b > a:
    h = h[:a] + h[b + len('</script>'):]
    print("  已移除旧 v15")

blk = r'''<script id="v18">
(function(){
  var PORT = 8000, CACHE = null, CACHE_AT = 0;
  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"]/g, function(c){ return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'})[c]; }); }
  function loadDevs(force){
    if (!force && CACHE && Date.now() - CACHE_AT < 3000) return Promise.resolve(CACHE);
    return fetch('/api/devices').then(function(r){ return r.json(); }).then(function(j){
      CACHE = j.devices || []; CACHE_AT = Date.now(); return CACHE;
    }).catch(function(){ return CACHE || []; });
  }
  function post(path, body){
    return fetch(path, {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body)})
      .then(function(r){ return r.json(); }).catch(function(){ return null; });
  }
  function dialog(title, bodyEl){
    if (typeof openModal === 'function') { openModal({title: title, sub: '', bodyEl: bodyEl, auto: true}); return; }
    var ov = document.createElement('div');
    ov.style.cssText = 'position:fixed;inset:0;background:#05080d;z-index:300;display:flex;align-items:center;justify-content:center;padding:20px';
    var box = document.createElement('div');
    box.style.cssText = 'background:#0d1421;border:1px solid #232d40;border-radius:12px;padding:18px;max-width:90vw;max-height:86vh;overflow:auto';
    var t = document.createElement('div'); t.textContent = title; t.style.cssText = 'font-size:15px;font-weight:650;color:#e6edf7;margin-bottom:12px';
    box.appendChild(t); box.appendChild(bodyEl); ov.appendChild(box);
    ov.addEventListener('click', function(e){ if (e.target === ov) ov.remove(); });
    document.body.appendChild(ov);
  }
  function streamURL(serial){
    var base = location.hostname || '131.255.36.102';
    var ws = encodeURIComponent('ws://' + base + ':' + PORT + '/?action=proxy-adb&remote=tcp%3A8886&udid=' + serial);
    return 'http://' + base + ':' + PORT + '/#!action=stream&udid=' + encodeURIComponent(serial) +
           '&player=mse&ws=' + ws + '&fitToScreen=true&bitrate=8000000&maxSize=1280';
  }
  function openLive(serial){
    var w = document.createElement('div');
    w.innerHTML = '<div style="display:flex;flex-direction:column;gap:10px;width:min(760px,88vw)">' +
      '<iframe allow="autoplay; fullscreen" style="width:100%;height:min(70vh,740px);border:0;border-radius:10px;background:#000"></iframe>' +
      '<div class="lk" style="display:flex;gap:8px;justify-content:center"></div></div>';
    w.querySelector('iframe').src = streamURL(serial);
    var keys = w.querySelector('.lk');
    [['back','返回'],['home','Home'],['app_switch','最近'],['notifications','通知'],['wakeup','唤醒']].forEach(function(k){
      var b = document.createElement('button');
      b.textContent = k[1];
      b.style.cssText = 'padding:8px 16px;border-radius:8px;border:1px solid #232d40;background:#151c2b;color:#c9d4e4;cursor:pointer';
      b.addEventListener('click', function(){ post('/api/key', {serial: serial, key: k[0]}); });
      keys.appendChild(b);
    });
    dialog('实时画面 · ' + serial, w.firstChild);
  }
  function openDetail(serial){
    loadDevs(true).then(function(list){
      var d = (list || []).find(function(x){ return x.serial === serial; }) || {serial: serial};
      var lease = d.lease && d.lease.owner ? ('占用中 · ' + d.lease.owner + (d.lease.remaining_s != null ? ' · 剩 ' + Math.round(d.lease.remaining_s) + 's' : '')) : '空闲';
      var blk = (d.blockers || []).map(function(x){ return x.msg + ' → ' + x.fix; }).join('<br>');
      var caps = (d.capabilities || []).map(function(c){ return '<span style="font-size:11.5px;padding:4px 8px;border-radius:6px;background:#151c2b;border:1px solid #232d40;color:#8b98ad;margin:0 6px 6px 0;display:inline-block">' + esc(c) + '</span>'; }).join('');
      var box = document.createElement('div');
      box.style.cssText = 'display:flex;flex-direction:column;gap:12px';
      box.innerHTML =
        '<div class="dsec"><h4>名称</h4>' +
          '<div style="display:flex;gap:8px"><input id="aliasIn" placeholder="给这台起个名字，例如 华为-1 号位" style="flex:1;min-height:36px;padding:0 10px;border-radius:8px;background:#0b0f17;border:1px solid #232d40;color:#e6edf7">' +
          '<button id="aliasSave" style="padding:0 16px;border-radius:8px;background:#2f6feb;border:1px solid #2f6feb;color:#fff;font-weight:600;cursor:pointer">保存</button></div>' +
        '</div>' +
        '<div class="dsec"><h4>状态</h4><div style="display:grid;grid-template-columns:90px 1fr;gap:6px 10px;font-size:13px;color:#b7c2d4">' +
          '<b style="color:#7d8aa0">占用</b><span>' + esc(lease) + '</span>' +
          '<b style="color:#7d8aa0">可用</b><span>' + (d.usable ? '是' : ('否' + (blk ? '：' + blk : ''))) + '</span>' +
          '<b style="color:#7d8aa0">后端</b><span>' + esc(d.backend || '-') + ' · root=' + (d.root ? '是' : '否') + '</span>' +
          '<b style="color:#7d8aa0">屏幕</b><span>' + esc(d.screen || '-') + (d.screen_display_on === false ? '（熄灭）' : '') + '</span>' +
        '</div></div>' +
        '<div class="dsec"><h4>网络</h4><div style="display:grid;grid-template-columns:90px 1fr;gap:6px 10px;font-size:13px;color:#b7c2d4">' +
          '<b style="color:#7d8aa0">SSID</b><span>' + esc(d.wifi_ssid || '—') + '</span>' +
          '<b style="color:#7d8aa0">IP</b><span>' + esc(d.wifi_ip || '—') + '</span>' +
          '<b style="color:#7d8aa0">MAC</b><span>' + esc(d.wifi_mac || '—') + '</span>' +
        '</div></div>' +
        '<div class="dsec"><h4>能力（' + (d.capabilities || []).length + '）</h4><div>' + caps + '</div></div>' +
        '<div class="dsec"><h4>版本</h4><div style="display:grid;grid-template-columns:90px 1fr;gap:6px 10px;font-size:13px;color:#b7c2d4">' +
          '<b style="color:#7d8aa0">安卓</b><span>' + esc(d.android || '-') + ' · ' + esc(d.miui || '-') + '</span>' +
          '<b style="color:#7d8aa0">组件</b><span>' + esc('phone-use ' + ((d.versions || {}).phone_use || '-')) + ' · jar ' + esc((d.versions || {}).pu_jar_sha1 || '-') + '</span>' +
        '</div></div>' +
        '<div style="display:flex;gap:8px;flex-wrap:wrap">' +
          '<button data-a="live" style="padding:9px 16px;border-radius:8px;background:#2f6feb;border:1px solid #2f6feb;color:#fff;font-weight:600;cursor:pointer">实时画面</button>' +
          '<button data-a="lease" style="padding:9px 16px;border-radius:8px;background:#151c2b;border:1px solid #232d40;color:#c9d4e4;cursor:pointer">占用</button>' +
          '<button data-a="release" style="padding:9px 16px;border-radius:8px;background:#151c2b;border:1px solid #232d40;color:#c9d4e4;cursor:pointer">释放</button>' +
          '<button data-a="doctor" style="padding:9px 16px;border-radius:8px;background:#151c2b;border:1px solid #232d40;color:#c9d4e4;cursor:pointer">体检</button>' +
        '</div>';
      var inp = box.querySelector('#aliasIn');
      inp.value = d.alias || '';
      inp.placeholder = (d.model || '') + ' · 起个名字';
      box.querySelector('#aliasSave').addEventListener('click', function(){
        post('/api/alias', {serial: serial, name: inp.value}).then(function(){ CACHE_AT = 0; location.reload(); });
      });
      box.addEventListener('click', function(ev){
        var btn = ev.target.closest('[data-a]'); if (!btn) return;
        var a = btn.dataset.a;
        if (a === 'live') openLive(serial);
        if (a === 'lease') post('/api/lease', {serial: serial, owner: 'wall', ttl: 900}).then(function(){ CACHE_AT = 0; });
        if (a === 'release') post('/api/release', {serial: serial, owner: 'wall'}).then(function(){ CACHE_AT = 0; });
        if (a === 'doctor') { btn.textContent = '体检中…'; post('/api/doctor', {serial: serial}).then(function(r){
            btn.textContent = '体检'; var w = document.createElement('div');
            w.style.cssText = 'max-height:56vh;overflow:auto;font-size:12.5px;color:#b7c2d4;white-space:pre-wrap';
            w.textContent = JSON.stringify(r, null, 2); dialog('体检 · ' + serial, w); }); }
      });
      dialog((d.alias || d.model || serial) + ' · ' + serial, box);
    });
  }
  /* 卡片标题优先显示别名 */
  function paintAlias(){
    loadDevs().then(function(list){
      document.querySelectorAll('.card').forEach(function(card){
        var img = card.querySelector('img.screen'); if (!img) return;
        var m = /\/screen\/([^\/?#]+)/.exec(img.getAttribute('src') || ''); if (!m) return;
        var d = (list || []).find(function(x){ return x.serial === decodeURIComponent(m[1]); });
        if (!d || !d.alias) return;
        var title = card.querySelector('.card-title, h3, .name');
        if (title && title.textContent.indexOf(d.alias) < 0) {
          title.textContent = d.alias;
          var sub = card.querySelector('.card-sub, .sub');
          if (sub && sub.textContent.indexOf(d.serial) < 0) sub.textContent = d.serial + ' · ' + (d.model || '');
        }
      });
    });
  }
  setInterval(paintAlias, 2000);
  document.addEventListener('click', function(ev){
    if (ev.target.closest('button, a, input, iframe, .modal')) return;
    var card = ev.target.closest('.card'); if (!card) return;
    var img = card.querySelector('img.screen'); if (!img) return;
    var m = /\/screen\/([^\/?#]+)/.exec(img.getAttribute('src') || '');
    if (m) { ev.stopPropagation(); ev.preventDefault(); openDetail(decodeURIComponent(m[1])); }
  }, true);
})();
</script>'''
h = h.replace('</body>', blk + '\n</body>')
open(PAGE, 'w', encoding='utf-8').write(h)
print("  前端已换成 v18（修正取数 + 命名）")
