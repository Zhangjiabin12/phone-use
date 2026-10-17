import subprocess

p = '/usr/local/share/phone-wall/wall-page.html'
s = open(p, encoding='utf-8').read()

if 'id="v14"' in s:
    print("已有 v14")
else:
    blk = r'''<script id="v14">
/* 每张卡显示「空闲 / 占用中（谁、剩多久）/ 不可用」，数据取自 hub 的 state/lease/usable */
(function(){
  function stateOf(d){
    if (d.present === false) return {t:'离线', cls:'off', tip:'不在 adb 列表里'};
    if (d.usable === false) {
      var b = (d.blockers || [])[0];
      return {t:'不可用', cls:'bad', tip: b ? b.msg : '不满足无人值守条件'};
    }
    var l = d.lease;
    if (l && l.owner) {
      var rem = l.remaining_s != null ? '剩 ' + Math.max(0, Math.round(l.remaining_s)) + 's' : '';
      return {t:'占用中 · ' + l.owner + (rem ? ' · ' + rem : ''), cls:'busy', tip:'被 ' + l.owner + ' 占用'};
    }
    if (d.using || d.state === 'busy') return {t:'使用中', cls:'busy', tip:'有任务在执行'};
    return {t:'空闲', cls:'ok', tip:'可派任务'};
  }
  function paint(){
    var ds = (window.S && S.devices) ? S.devices : [];
    document.querySelectorAll('img.screen').forEach(function(img){
      var m = /\/screen\/([^\/?#]+)/.exec(img.getAttribute('src') || img.src || '');
      if (!m) return;
      var serial = decodeURIComponent(m[1]);
      var card = img.closest('.card'); if (!card) return;
      var d = ds.find(function(x){ return x.serial === serial; }); if (!d) return;
      var st = stateOf(d);
      var el = card.querySelector('.live-state');
      if (!el) {
        el = document.createElement('span');
        el.className = 'live-state';
        var host = card.querySelector('.card-head') || card.firstElementChild || card;
        host.appendChild(el);
      }
      if (el.dataset.s !== st.t) {
        el.dataset.s = st.t;
        el.textContent = st.t;
        el.className = 'live-state ' + st.cls;
        el.title = st.tip;
      }
    });
  }
  setInterval(paint, 1200);
  paint();
})();
</script>
<style id="v14s">
.live-state{display:inline-flex;align-items:center;gap:6px;padding:3px 9px;border-radius:999px;
  font-size:12px;white-space:nowrap;border:1px solid #2a3448;background:#161d2b;color:#b7c2d4;margin-left:8px}
.live-state:before{content:'';width:7px;height:7px;border-radius:50%;background:#8b98ad}
.live-state.ok{color:#56d364;border-color:rgba(63,185,80,.35);background:rgba(63,185,80,.10)}
.live-state.ok:before{background:#3fb950}
.live-state.busy{color:#e3b341;border-color:rgba(210,153,34,.35);background:rgba(210,153,34,.10)}
.live-state.busy:before{background:#d29922}
.live-state.bad{color:#ff7b72;border-color:rgba(248,81,73,.35);background:rgba(248,81,73,.10)}
.live-state.bad:before{background:#f85149}
.live-state.off{color:#8b98ad}
</style>'''
    s = s.replace('</body>', blk + '\n</body>')
    open(p, 'w', encoding='utf-8').write(s)
    print("已注入 v14：卡片显示 空闲 / 占用中(谁·剩多久) / 不可用 / 离线")
