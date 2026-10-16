import re
p = r'E:\dsh_project\远程桌面 36.102\wall-page.html'
s = open(p, encoding='utf-8').read()
btns = '''<div class="keybar">
      <button class="btn btn-sm" data-key="back" type="button">返回</button>
      <button class="btn btn-sm" data-key="home" type="button">Home</button>
      <button class="btn btn-sm" data-key="app_switch" type="button">最近</button>
      <button class="btn btn-sm" data-key="notifications" type="button">通知</button>
      <button class="btn btn-sm" data-key="wakeup" type="button">唤醒</button>
    </div>'''
s2 = re.sub(r'<div class="keybar">\s*</div>', btns, s)
if s2 == s:
    s2 = re.sub(r'<div class="keybar">.*?</div>', btns, s, count=1, flags=re.S)
open(p, 'w', encoding='utf-8').write(s2)
print('data-key 按钮数 =', s2.count('data-key='))
print('keybar 容器 =', s2.count('class="keybar"'))
print('takeover 按钮 =', 'data-act="takeover"' in s2, '| takeover 函数 =', 'async function takeover' in s2)
