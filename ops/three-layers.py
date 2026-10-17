p = '/usr/local/share/phone-wall/wall-page.html'
s = open(p, encoding='utf-8').read()

if 'id="v15"' in s:
    print("已有 v15")
else:
    blk = r'''<style id="v15s">
/* 第一层：总览不渲染任何画面，只留元信息 —— 设备多了也不吃 CPU */
.card .phone{display:none !important}
.card{cursor:pointer}
.card:hover{outline:1px solid rgba(47,111,235,.45)}
.detail{display:flex;flex-direction:column;gap:14px;min-width:min(720px,86vw);max-width:86vw}
.detail .dsec{border:1px solid #232d40;border-radius:10px;padding:12px 14px;background:#111826}
.detail .dsec h4{margin:0 0 8px;font-size:13px;color:#8b98ad;font-weight:600;letter-spacing:.02em}
.detail .kv{display:grid;grid-template-columns:88px 1fr;gap:6px 10px;font-size:13px;color:#b7c2d4}
.detail .kv b{color:#7d8aa0;font-weight:500}
.detail .dbtns{display:flex;flex-wrap:wrap;gap:8px}
.detail .dbtns button{padding:8px 14px;border-radius:8px;border:1px solid #232d40;background:#151c2b;color:#c9d4e4;cursor:pointer;font-size:13px}
.detail .dbtns button.primary{background:#2f6feb;border-color:#2f6feb;color:#fff;font-weight:600}
.detail .dbtns button:hover{background:#1b2436}
.live-wrap{display:flex;flex-direction:column;gap:10px;width:min(760px,90vw)}
.live-wrap iframe{width:100%;height:min(72vh,760px);border:0;border-radius:10px;background:#000}
.live-keys{display:flex;gap:8px;justify-content:center}
.live-keys button{padding:8px 16px;border-radius:8px;border:1px solid #232d40;background:#151c2b;color:#c9d4e4;cursor:pointer}
</style>
<script id="v15">
(function(){
  var PORT = 8000;
  function devs(){ return (window.S && S.devices) ? S.devices : []; }
  function dev(serial){ return devs().find(function(x){ return x.serial === serial; }); }
  function post(path, body){
    return fetch(path, {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body)}).then(function(r){ return r.json(); }).catch(function(){ return null; });
  }
  function esc(s){ return String(s == null ? '' : s).replace(/[&<>]/g, function(c){ return ({'&':'&amp;','<':'&lt;','>':'&gt;'})[c]; }); }
  function modal(title, bodyEl){
    if (typeof openModal === 'function') { openModal({title: title, sub: '', bodyEl: bodyEl, auto: true}); return; }
    var ov = document.createElement('div');
    ov.style.cssText = 'position:fixed;inset:0;background:#05080d;z-index:300;display:flex;align-items:center;justify-content:center;padding:20px';
    var box = document.createElement('div'); box.style.cssText = 'background:#0d1421;border:1px solid #232d40;border-radius:12px;padding:18px';
    box.appendChild(bodyEl); ov.appendChild(box);
    ov.addEventListener('click', function(e){ if (e.target === ov) ov.remove(); });
    document.body.appendChild(ov);
  }
  function streamURL(serial){
    var base = location.hostname || '131.255.36.102';
    var ws = encodeURIComponent('ws://' + base + ':' + PORT + '/?action=proxy-adb&remote=tcp%3A8886&udid=' + serial);
    return 'http://' + base + ':' + PORT + '/#!action=stream&udid=' + encodeURIComponent(serial) +
           '&player=mse&ws=' + ws + '&fitToScreen=true&bitrate=8000000&maxSize=1280';
  }
  /* 第三层：实时画面（同一时刻只允许一路） */
  function openLive(serial){
    var wrap = document.createElement('div'); wrap.className = 'live-wrap';
    var f = document.createElement('iframe');
    f.src = streamURL(serial); f.setAttribute('allow', 'autoplay; fullscreen'); f.title = serial;
    wrap.appendChild(f);
    var keys = document.createElement('div'); keys.className = 'live-keys';
    [['back','返回'],['home','Home'],['app_switch','最近'],['notifications','通知'],['wakeup','唤醒']].forEach(function(k){
      var b = document.createElement('button'); b.textContent = k[1];
      b.addEventListener('click', function(){ post('/api/key', {serial: serial, key: k[0]}); });
      keys.appendChild(b);
    });
    wrap.appendChild(keys);
    modal('实时画面 · ' + serial, wrap);
  }
  /* 第二层：单台详情 */
  function openDetail(serial){
    var d = dev(serial) || {serial: serial};
    var box = document.createElement('div'); box.className = 'detail';
    var lease = d.lease && d.lease.owner ? ('占用中 · ' + d.lease.owner + (d.lease.remaining_s != null ? ' · 剩 ' + Math.round(d.lease.remaining_s) + 's' : '')) : '空闲';
    var blk = (d.blockers || []).map(function(b){ return b.msg + ' → ' + b.fix; }).join('<br>');
    box.innerHTML =
      '<div class="dsec"><h4>状态</h4><div class="kv">' +
        '<b>占用</b><span>' + esc(lease) + '</span>' +
        '<b>可用</b><span>' + (d.usable ? '是（可无人值守）' : '否' + (blk ? '：' + blk : '')) + '</span>' +
        '<b>后端</b><span>' + esc(d.backend || '-') + ' · root=' + (d.root ? '是' : '否') + '</span>' +
        '<b>屏幕</b><span>' + esc(d.screen || '-') + (d.screen_display_on === false ? '（熄灭）' : '') + '</span>' +
      '</div></div>' +
      '<div class="dsec"><h4>网络</h4><div class="kv">' +
        '<b>SSID</b><span>' + esc(d.wifi_ssid || '—') + '</span>' +
        '<b>IP</b><span>' + esc(d.wifi_ip || '—') + '</span>' +
        '<b>MAC</b><span>' + esc(d.wifi_mac || '—') + '</span>' +
      '</div></div>' +
      '<div class="dsec"><h4>能力（' + ((d.capabilities || []).length) + '）</h4><div style="display:flex;flex-wrap:wrap;gap:6px">' +
        (d.capabilities || []).map(function(c){ return '<span style="font-size:11.5px;padding:4px 8px;border-radius:6px;background:#151c2b;border:1px solid #232d40;color:#8b98ad">' + esc(c) + '</span>'; }).join('') +
      '</div></div>' +
      '<div class="dsec"><h4>版本</h4><div class="kv">' +
        '<b>安卓</b><span>' + esc(d.android || '-') + ' · ' + esc(d.miui || '-') + '</span>' +
        '<b>组件</b><span>' + esc((d.versions && ('phone-use ' + d.versions.phone_use + ' · jar ' + d.versions.pu_jar_sha1)) || '-') + '</span>' +
      '</div></div>' +
      '<div class="dbtns">' +
        '<button class="primary" data-a="live">实时画面</button>' +
        '<button data-a="lease">占用</button>' +
        '<button data-a="release">释放</button>' +
        '<button data-a="doctor">体检</button>' +
      '</div>';
    box.querySelector('.dbtns').addEventListener('click', async function(ev){
      var b = ev.target.closest('button'); if (!b) return;
      var a = b.dataset.a;
      if (a === 'live') return openLive(serial);
      if (a === 'lease') { await post('/api/lease', {serial: serial, owner: 'wall', ttl: 900}); }
      if (a === 'release') { await post('/api/release', {serial: serial, owner: 'wall'}); }
      if (a === 'doctor') { b.textContent = '体检中…'; var r = await post('/api/doctor', {serial: serial}); b.textContent = '体检'; if (r) modal('体检 · ' + serial, (function(){ var w=document.createElement('div'); w.style.cssText='max-height:60vh;overflow:auto;font-size:13px;color:#b7c2d4;white-space:pre-wrap'; w.textContent = JSON.stringify(r, null, 2); return w; })()); }
    });
    modal((d.model || serial) + ' · ' + serial, box);
  }
  /* 第一层：点卡片（避开按钮）进第二层 */
  document.addEventListener('click', function(ev){
    if (ev.target.closest('button, a, input, iframe, .modal')) return;
    var card = ev.target.closest('.card'); if (!card) return;
    var img = card.querySelector('img.screen');
    var m = img && /\/screen\/([^\/?#]+)/.exec(img.getAttribute('src') || '');
    if (m) openDetail(decodeURIComponent(m[1]));
  }, false);
})();
</script>'''
    s = s.replace('</body>', blk + '\n</body>')
    open(p, 'w', encoding='utf-8').write(s)
    print("已注入 v15：三层结构（总览不含画面 / 详情 / 实时流）")
