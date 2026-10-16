
---

## 怎么看 / 怎么点（视觉与点击手册 · 给 agent 的硬规矩）

### 一、看屏幕：只能用 `phone-look`（agent 的工具输出是文本，看不到图）
```bash
phone-look <serial> "现在是什么页面？有没有需要先处理的弹窗？"     # 回文本结论
phone-look <serial> --coord "WLAN 列表里 'test-portal2' 这一项"   # 额外给 TAP=x,y
```
- 它内部做：`screencap → 取回本地 → 交给视觉模型（deepseek-flash，已实测能准确读真机截图）→ 回文本`
- 结论里若带 `TAP=x,y`，就是可直接点的**设备绝对坐标**
- 想要原始截图存档（备查/给人看）：`phone-use shot /sdcard/s.png` + `phone-use pull /sdcard/s.png /tmp/s.png`
- **坐标永远是设备真实分辨率**（先 `phone-use state` 读 `screen`）：华为 1236×2676、小米 1080×2340 —— **别猜**

### 二、点屏幕：三级精度，从上到下选（能用上面的就别用下面的）
| 级别 | 命令 | 什么时候用 |
|---|---|---|
| ① 语义点击（最稳） | `phone-use click-text "登录"` / `click-desc "下一步"` / `click-id !account` | 控件有文字/描述/id（设置项、按钮、WebView 表单） |
| ② 元素定位（推荐默认） | `phone-use find "WLAN"` / `ui WLAN` → 拿到 `bounds` → 算中心 → `phone-use click-xy X Y` | 有控件但文字不唯一；**P3 机型（只能节点动作）也只有这条路** |
| ③ 视觉估坐标 | `phone-look --coord "…"` → `phone-use tap X Y` | 自绘界面 / WebView 不暴露元素 / 上面两条都失败时 |
- 输入文字：`phone-use settext --id !account "zjb"`（优先）或 `phone-use input "文本"`；有 root 也可 `key`
- 按键：`phone-use key back|home|app_switch|enter…`；**不要用 `adb shell input`**（MIUI/HyperOS 会被 `INJECT_EVENTS` 拦；`phone-use` 会自动按 P1 root / P2 input / P3 jar 回退）

### 三、判定纪律（不许拿返回码当成功）
- 上线成功 = `wifi` 里 **ssid 匹配 + supplicant=COMPLETED + ip 非空**
- 1X 成功 = 同上 **+ `failure` 里 level2FailureCode=NONE**
- 门户成功 = `probe` 里 **portal_intercepted=false**（普通公网地址 302→301；`generate_204` 可能被 permit 名单放行成假 204，**不能当证据**）
- 连续 2 次同类失败 → 换招或如实报 FAIL，不要卡在同一步重复

### 四、改东西的规矩（底层冻结）
- `/opt/phone-use/base/**` 是**已跑通的底层，只读**：`phone-use`、`SKILL.md`、`ONBOARD.md`、hub/服务代码 —— **禁止编辑**
- 要改必须先复制再改：`cp /opt/phone-use/base/X /opt/phone-use/work/copies/X.<时间戳>`，改那份（默认不生效，作为提案）
- **自适配请写数据，不要写代码**：把新机型差异追加到 `/opt/phone-use/work/adapt/<机型>.yaml`，例如
  ```yaml
  HUAWEI-BRQ-AN00:
    cmd_wifi_connect: false      # HyperOS/部分鸿蒙不允许 shell 连网 → 走界面或门户协议式
    input_backend: input         # 免 root 但允许坐标注入
  ```
- `phone-use` 启动时会做 base 的 sha256 校验；**校验不过就拒绝执行**（防止"偷偷改了底层"）
