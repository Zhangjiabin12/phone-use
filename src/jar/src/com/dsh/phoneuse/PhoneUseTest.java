package com.dsh.phoneuse;

import com.android.uiautomator.testrunner.UiAutomatorTestCase;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;

/**
 * phone-use 的「节点点击」注入器 —— 跑在 adb 侧 uiautomator runtest 里，免 root、免装 APK。
 *
 * 为什么能绕开小米的限制：走的是无障碍的**节点动作**（ACTION_CLICK / ACTION_SET_TEXT），
 * 不是坐标手势（dispatchGesture），所以不需要 CAN_PERFORM_GESTURES 能力位。
 *
 * 全部用反射调用 Android API，因此只依赖 JDK 编译（不需要 android.jar）。
 *
 * 用法：
 *   adb push pu_cmd.txt /sdcard/pu_cmd.txt
 *   adb shell uiautomator runtest pu.jar -c com.dsh.phoneuse.PhoneUseTest#testRun
 *   adb shell cat /sdcard/pu_out.txt
 *
 * 命令（每行一条，# 开头为注释）：
 *   ui | find <子串> | click-text <子串> | click-desc <子串> | click-id <子串>
 *   settext <文本> | global <home|back|recents|notifications>
 *   shot <路径> | tap <x> <y> | swipe <x1> <y1> <x2> <y2> [ms]
 *   shell <命令> | wait <毫秒>
 */
public class PhoneUseTest extends UiAutomatorTestCase {

    private static final String CMD = "/sdcard/pu_cmd.txt";
    private static final String OUT = "/sdcard/pu_out.txt";
    private static final int MAX_DUMP = 400;

    private Object ua;                 // android.app.UiAutomation
    private PrintWriter out;

    public void testRun() throws Exception {
        ua = resolveUiAutomation();
        out = new PrintWriter(new FileWriter(OUT, false), true);
        out.println("UiAutomation = " + (ua == null ? "null ✗" : ua.getClass().getName()));
        List<String> cmds = readLines(CMD);
        out.println("BEGIN commands=" + cmds.size() + " gestures=" + probeGesture());
        for (String line : cmds) {
            String c = line.trim();
            if (c.isEmpty() || c.startsWith("#")) {
                continue;
            }
            out.println("$ " + c);
            try {
                dispatch(c);
            } catch (Throwable t) {
                out.println("ERR " + t.getClass().getSimpleName() + ": " + t.getMessage());
            }
            out.flush();
        }
        out.println("END");
        out.close();
    }

    // ---------------- 命令分发 ----------------

    // ---------------- 找到 UiAutomation ----------------

    /**
     * UiAutomator 1.x 的 UiAutomatorTestCase 在 Android 12 上并不继承 InstrumentationTestCase，
     * 所以拿不到 getInstrumentation()。这里从 runner 注入的 UiDevice 里把 UiAutomation 反射挖出来。
     */
    private Object resolveUiAutomation() {
        Object dev = null;
        try {
            dev = call(this, "getUiDevice");
        } catch (Throwable ignore) {
        }
        if (dev == null) {
            try {
                dev = call(Class.forName("com.android.uiautomator.core.UiDevice"), "getInstance");
            } catch (Throwable ignore) {
            }
        }
        Object found = dev == null ? null : dig(dev, "android.app.UiAutomation", 5);
        if (found != null) {
            return found;
        }
        // 兜底：ActivityThread → Instrumentation → getUiAutomation()
        try {
            Object at = call(Class.forName("android.app.ActivityThread"), "currentActivityThread");
            Object instr = call(at, "getInstrumentation");
            return call(instr, "getUiAutomation");
        } catch (Throwable t) {
            return null;
        }
    }

    /** 在对象图里找第一个指定类型的实例（只往 android./com.android. 的字段里钻） */
    private static Object dig(Object root, String className, int depth) {
        if (root == null || depth < 0) {
            return null;
        }
        if (className.equals(root.getClass().getName())) {
            return root;
        }
        for (Class<?> c = root.getClass(); c != null && c != Object.class; c = c.getSuperclass()) {
            for (Field f : c.getDeclaredFields()) {
                if (java.lang.reflect.Modifier.isStatic(f.getModifiers())) {
                    continue;
                }
                String fn = f.getType().getName();
                boolean interesting = className.equals(fn)
                        || fn.startsWith("android.") || fn.startsWith("com.android.");
                if (!interesting) {
                    continue;
                }
                try {
                    f.setAccessible(true);
                    Object v = f.get(root);
                    if (v == null) {
                        continue;
                    }
                    if (className.equals(v.getClass().getName())) {
                        return v;
                    }
                    if (fn.startsWith("com.android.uiautomator") || fn.startsWith("android.app")) {
                        Object r = dig(v, className, depth - 1);
                        if (r != null) {
                            return r;
                        }
                    }
                } catch (Throwable ignore) {
                }
            }
        }
        return null;
    }

    private void dispatch(String c) throws Exception {
        String[] a = split(c);
        String cmd = a[0];

        if ("ui".equals(cmd)) {
            dump(null);
        } else if ("find".equals(cmd)) {
            dump(a[1]);
        } else if ("click-text".equals(cmd)) {
            click(find(strip(a[1]), 0), self(a[1]));
        } else if ("click-desc".equals(cmd)) {
            click(find(strip(a[1]), 1), self(a[1]));
        } else if ("click-id".equals(cmd)) {
            click(find(strip(a[1]), 2), self(a[1]));
        } else if ("settext".equals(cmd)) {
            setText(c.length() > 8 ? c.substring(8) : "");
        } else if ("settext-id".equals(cmd)) {
            // settext-id <元素id> <文本>：WebView 输入框用这个最稳
            setTextOn(find(a[1], 2), a.length > 2 ? c.substring(c.indexOf(a[2])) : "");
        } else if ("global".equals(cmd)) {
            int g = "back".equals(a[1]) ? 1 : "home".equals(a[1]) ? 2 : "recents".equals(a[1]) ? 3 : 4;
            out.println("global " + a[1] + " -> " + call(ua, "performGlobalAction", Integer.valueOf(g)));
        } else if ("shot".equals(cmd)) {
            shot(a[1]);
        } else if ("tap".equals(cmd)) {
            out.println("tap -> " + gesture(f(a[1]), f(a[2]), f(a[1]), f(a[2]), 60));
        } else if ("click-xy".equals(cmd)) {
            clickAt(Integer.parseInt(a[1]), Integer.parseInt(a[2]));
        } else if ("scroll".equals(cmd)) {
            scroll(4096, a.length > 1 ? Integer.parseInt(a[1]) : 1);      // ACTION_SCROLL_FORWARD
        } else if ("scroll-up".equals(cmd)) {
            scroll(8192, a.length > 1 ? Integer.parseInt(a[1]) : 1);      // ACTION_SCROLL_BACKWARD
        } else if ("swipe".equals(cmd)) {
            out.println("swipe -> " + gesture(f(a[1]), f(a[2]), f(a[3]), f(a[4]),
                    a.length > 5 ? Long.parseLong(a[5]) : 300));
        } else if ("shell".equals(cmd)) {
            String sh = c.substring(6);
            out.println("shell> " + sh);
            out.println(shell(sh));
        } else if ("http".equals(cmd)) {
            http("GET", a[1], null);
        } else if ("httpfile".equals(cmd)) {
            httpFile(a[1], a[2]);
        } else if ("portal-login".equals(cmd)) {
            portalAuth("account " + (c.length() > 13 ? c.substring(13) : ""));
        } else if ("portal-free".equals(cmd)) {
            portalAuth("free");
        } else if ("portal-noper".equals(cmd)) {
            portalAuth("noper");
        } else if ("httppost".equals(cmd)) {
            http("POST", a[1], c.length() > 9 ? c.substring(9) : "");
        } else if ("wait".equals(cmd)) {
            Thread.sleep(Long.parseLong(a[1]));
            out.println("waited " + a[1]);
        } else {
            out.println("ERR unknown command: " + cmd);
        }
    }

    // ---------------- 元素树 ----------------

    private void dump(String filter) throws Exception {
        Object root = call(ua, "getRootInActiveWindow");
        if (root == null) {
            out.println("ui: root == null");
            return;
        }
        List<Object> all = new ArrayList<Object>();
        collect(root, all, 0);
        int shown = 0;
        for (Object n : all) {
            String d = describe(n);
            if (filter != null && !d.toLowerCase().contains(filter.toLowerCase())) {
                continue;
            }
            out.println(d);
            if (++shown >= MAX_DUMP) {
                break;
            }
        }
        out.println("ui: 共 " + all.size() + " 节点，输出 " + shown);
    }

    private void collect(Object node, List<Object> acc, int depth) throws Exception {
        if (node == null || depth > 40 || acc.size() > 3000) {
            return;
        }
        acc.add(node);
        int n = (Integer) call(node, "getChildCount");
        for (int i = 0; i < n; i++) {
            collect(call(node, "getChild", Integer.valueOf(i)), acc, depth + 1);
        }
    }

    /** mode: 0=text 1=contentDescription 2=viewIdResourceName；先精确匹配，再退化为包含匹配 */
    private Object find(String needle, int mode) throws Exception {
        Object exact = findInternal(needle, mode, true);
        if (exact != null) {
            return exact;
        }
        return findInternal(needle, mode, false);
    }

    private Object findInternal(String needle, int mode, boolean exact) throws Exception {
        Object root = call(ua, "getRootInActiveWindow");
        if (root == null) {
            out.println("find: root == null");
            return null;
        }
        List<Object> all = new ArrayList<Object>();
        collect(root, all, 0);
        String want = needle.toLowerCase();
        for (Object n : all) {
            String v = mode == 0 ? s(call(n, "getText"))
                    : mode == 1 ? s(call(n, "getContentDescription"))
                    : s(call(n, "getViewIdResourceName"));
            if (v == null) {
                continue;
            }
            String lv = v.toLowerCase();
            if (exact ? lv.equals(want) : lv.contains(want)) {
                return n;
            }
        }
        if (!exact) {
            out.println("find: 没找到 " + needle);
        }
        return null;
    }

    private void click(Object node, boolean forceSelf) throws Exception {
        if (node == null) {
            return;
        }
        if (forceSelf) {
            // WebView 里的元素常常 isClickable()=false，但 ACTION_CLICK 交给 WebView 就能生效
            out.println("click(self) ok=" + call(node, "performAction", Integer.valueOf(16))
                    + " node=" + describe(node));
            return;
        }
        Object cur = node;
        for (int i = 0; i < 6 && cur != null; i++) {
            if (Boolean.TRUE.equals(call(cur, "isClickable"))) {
                out.println("click ok=" + call(cur, "performAction", Integer.valueOf(16)) // ACTION_CLICK
                        + " node=" + describe(cur));
                return;
            }
            cur = call(cur, "getParent");
        }
        out.println("click(force) ok=" + call(node, "performAction", Integer.valueOf(16))
                + " node=" + describe(node));
    }

    /** 参数以 ! 开头表示「点这个元素本身」，不上溯可点祖先（WebView 元素需要） */
    private static boolean self(String arg) {
        return arg != null && arg.startsWith("!");
    }

    private static String strip(String arg) {
        return arg != null && arg.startsWith("!") ? arg.substring(1) : arg;
    }

    private void setText(String text) throws Exception {
        Object root = call(ua, "getRootInActiveWindow");
        if (root == null) {
            out.println("settext: root == null");
            return;
        }
        Object target = call(root, "findFocus", Integer.valueOf(1)); // FOCUS_INPUT
        if (target == null || !Boolean.TRUE.equals(call(target, "isEditable"))) {
            List<Object> all = new ArrayList<Object>();
            collect(root, all, 0);
            target = null;
            for (Object n : all) {
                if (Boolean.TRUE.equals(call(n, "isEditable"))) {
                    target = n;
                    break;
                }
            }
        }
        setTextOn(target, text);
    }

    private void setTextOn(Object target, String text) throws Exception {
        if (target == null) {
            out.println("settext: 没找到输入框");
            return;
        }
        Object bundle = Class.forName("android.os.Bundle").getDeclaredConstructor().newInstance();
        call(bundle, "putString", "ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE", text);
        out.println("settext ok=" + call(target, "performAction", Integer.valueOf(2097152), bundle) // ACTION_SET_TEXT
                + " node=" + describe(target));
    }

    private String describe(Object n) throws Exception {
        Object rect = Class.forName("android.graphics.Rect").getDeclaredConstructor().newInstance();
        call(n, "getBoundsInScreen", rect);
        return String.format("%s | id=%s | text=%s | desc=%s | click=%s edit=%s focus=%s | [%s,%s][%s,%s]",
                shortName(s(call(n, "getClassName"))), s(call(n, "getViewIdResourceName")),
                s(call(n, "getText")), s(call(n, "getContentDescription")),
                call(n, "isClickable"), call(n, "isEditable"), call(n, "isFocused"),
                field(rect, "left"), field(rect, "top"), field(rect, "right"), field(rect, "bottom"));
    }

    // ---------------- 手势（对照用）与截图 ----------------

    private boolean gesture(float x1, float y1, float x2, float y2, long ms) {
        try {
            Class<?> pathC = Class.forName("android.graphics.Path");
            Object path = pathC.getDeclaredConstructor().newInstance();
            call(path, "moveTo", Float.valueOf(x1), Float.valueOf(y1));
            call(path, "lineTo", Float.valueOf(x2), Float.valueOf(y2));
            Class<?> strokeC = Class.forName("android.accessibilityservice.GestureDescription$StrokeDescription");
            Object stroke = strokeC.getConstructor(pathC, long.class, long.class)
                    .newInstance(path, Long.valueOf(0), Long.valueOf(ms));
            Class<?> builderC = Class.forName("android.accessibilityservice.GestureDescription$Builder");
            Object builder = builderC.getDeclaredConstructor().newInstance();
            call(builder, "addStroke", stroke);
            Object g = call(builder, "build");
            return Boolean.TRUE.equals(call(ua, "dispatchGesture", g, null, null));
        } catch (Throwable t) {
            out.println("gesture ERR " + t);
            return false;
        }
    }

    private boolean probeGesture() {
        return gesture(1, 1, 1, 1, 50);
    }

    private void shot(String path) throws Exception {
        Object bmp = call(ua, "takeScreenshot");
        if (bmp == null) {
            out.println("shot FAILED (null)");
            return;
        }
        Class<?> fmt = Class.forName("android.graphics.Bitmap$CompressFormat");
        Object png = fmt.getField("PNG").get(null);
        FileOutputStream fos = new FileOutputStream(new File(path));
        call(bmp, "compress", png, Integer.valueOf(100), fos);
        fos.close();
        out.println("shot OK " + path + " " + new File(path).length() + " bytes");
    }

    // ---------------- HTTP（门户认证用：请求必须由手机自己发出） ----------------

    private void http(String method, String url, String body) {
        try {
            java.net.HttpURLConnection conn = (java.net.HttpURLConnection) new java.net.URL(url).openConnection();
            conn.setInstanceFollowRedirects(false);
            conn.setConnectTimeout(10000);
            conn.setReadTimeout(15000);
            conn.setRequestMethod(method);
            conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 12) phone-use");
            if (body != null && !body.isEmpty()) {
                conn.setDoOutput(true);
                conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded");
                conn.getOutputStream().write(body.getBytes("UTF-8"));
            }
            int code = conn.getResponseCode();
            out.println("http " + method + " " + url + " -> " + code + " " + conn.getResponseMessage());
            String loc = conn.getHeaderField("Location");
            if (loc != null) {
                out.println("   Location: " + loc);
            }
            java.io.InputStream is = code >= 400 ? conn.getErrorStream() : conn.getInputStream();
            if (is == null && code >= 300) {
                is = conn.getErrorStream();
            }
            if (is != null) {
                byte[] buf = new byte[4096];
                int n = is.read(buf);
                is.close();
                if (n > 0) {
                    String s = new String(buf, 0, n, "UTF-8").replace("\n", " ").replace("\r", " ");
                    out.println("   body[" + n + "]: " + (s.length() > 1200 ? s.substring(0, 1200) + "…" : s));
                }
            }
        } catch (Throwable t) {
            out.println("http ERR " + t);
        }
    }

    /** 把整个响应正文落到设备文件（自动跟 302，最多 5 跳，并打印跳转链） */
    private void httpFile(String url, String path) {
        try {
            java.net.HttpURLConnection conn = null;
            int code = 0;
            String cur = url;
            for (int hop = 0; hop < 6; hop++) {
                conn = (java.net.HttpURLConnection) new java.net.URL(cur).openConnection();
                conn.setInstanceFollowRedirects(false);
                conn.setConnectTimeout(10000);
                conn.setReadTimeout(20000);
                conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 12) phone-use");
                code = conn.getResponseCode();
                out.println("   hop" + hop + " " + code + " " + cur.substring(0, Math.min(90, cur.length())));
                if (code >= 300 && code < 400) {
                    String loc = conn.getHeaderField("Location");
                    if (loc == null) {
                        break;
                    }
                    cur = loc.startsWith("http") ? loc
                            : new java.net.URL(new java.net.URL(cur), loc).toString();
                    continue;
                }
                break;
            }
            java.io.InputStream is = code >= 400 ? conn.getErrorStream() : conn.getInputStream();
            if (is == null) {
                out.println("   无正文");
                return;
            }
            FileOutputStream fos = new FileOutputStream(new File(path));
            byte[] buf = new byte[16384];
            int n;
            long total = 0;
            while ((n = is.read(buf)) > 0) {
                fos.write(buf, 0, n);
                total += n;
            }
            fos.close();
            is.close();
            out.println("   已存 " + path + " " + total + " 字节（最终 " + code + " " + cur.substring(0, Math.min(80, cur.length())) + "）");
        } catch (Throwable t) {
            out.println("httpfile ERR " + t);
        }
    }

    // ---------------- 门户认证（由手机自己发起，凭据：账号 密码） ----------------

    private static class Resp {
        int code;
        String location;
        String body = "";
        String finalUrl = "";
    }

    /** 跨请求保持 Cookie（门户会话：Auth.do 会下发 JSESSIONID，doAuth 必须带回来） */
    private static final java.util.Map<String, String> COOKIES = new java.util.LinkedHashMap<String, String>();

    private static void captureCookies(java.net.HttpURLConnection conn) {
        try {
            for (java.util.Map.Entry<String, java.util.List<String>> e : conn.getHeaderFields().entrySet()) {
                if (e.getKey() == null || !"set-cookie".equalsIgnoreCase(e.getKey())) {
                    continue;
                }
                for (String v : e.getValue()) {
                    String kv = v.split(";")[0].trim();
                    int eq = kv.indexOf('=');
                    if (eq > 0) {
                        COOKIES.put(kv.substring(0, eq), kv);
                    }
                }
            }
        } catch (Throwable ignore) {
        }
    }

    private static String cookieHeader() {
        StringBuilder sb = new StringBuilder();
        for (String v : COOKIES.values()) {
            if (sb.length() > 0) {
                sb.append("; ");
            }
            sb.append(v);
        }
        return sb.toString();
    }

    private Resp request(String method, String url, String body, int maxHops) {
        Resp r = new Resp();
        String cur = url;
        try {
            for (int hop = 0; hop <= maxHops; hop++) {
                java.net.HttpURLConnection conn =
                        (java.net.HttpURLConnection) new java.net.URL(cur).openConnection();
                conn.setInstanceFollowRedirects(false);
                conn.setConnectTimeout(10000);
                conn.setReadTimeout(20000);
                conn.setRequestMethod(method);
                conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 12) phone-use");
                conn.setRequestProperty("X-Requested-With", "XMLHttpRequest");   // 门户是 jQuery ajax
                try {
                    java.net.URL u = new java.net.URL(cur);
                    conn.setRequestProperty("Referer", u.getProtocol() + "://" + u.getAuthority() + "/");
                    conn.setRequestProperty("Origin", u.getProtocol() + "://" + u.getAuthority());
                } catch (Throwable ignore) {
                }
                String ck = cookieHeader();
                if (!ck.isEmpty()) {
                    conn.setRequestProperty("Cookie", ck);
                }
                if (body != null && !body.isEmpty() && hop == 0) {
                    conn.setDoOutput(true);
                    conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded");
                    conn.getOutputStream().write(body.getBytes("UTF-8"));
                }
                r.code = conn.getResponseCode();
                captureCookies(conn);
                r.finalUrl = cur;
                r.location = conn.getHeaderField("Location");
                java.io.InputStream is = r.code >= 400 ? conn.getErrorStream() : conn.getInputStream();
                if (is != null) {
                    byte[] buf = new byte[8192];
                    int n = is.read(buf);
                    is.close();
                    if (n > 0) {
                        r.body = new String(buf, 0, n, "UTF-8");
                    }
                }
                if (r.code >= 300 && r.code < 400 && r.location != null && hop < maxHops) {
                    cur = r.location.startsWith("http") ? r.location
                            : new java.net.URL(new java.net.URL(cur), r.location).toString();
                    continue;
                }
                break;
            }
        } catch (Throwable t) {
            out.println("request ERR " + t);
        }
        return r;
    }

    /** portal-auth <free|noper|account> [账号] [密码]：探测 → 取 token → 认证 → 复核 */
    private void portalAuth(String args) {
        String[] a = split(args);
        String mode = a.length > 0 ? a[0] : "account";
        String account = a.length > 1 ? a[1] : "";
        String password = a.length > 2 ? a[2] : "";
        if ("account".equals(mode) && (account.isEmpty() || password.isEmpty())) {
            out.println("用法：portal-login <账号> <密码> / portal-free / portal-noper");
            return;
        }

        // 探测目标不能选被 permit 名单放行的 URL（generate_204 这类会被直接放行），用普通公网 IP
        Resp probe = request("GET", "http://1.1.1.1/", null, 0);
        String loc0 = probe.location == null ? "" : probe.location;
        boolean intercepted = loc0.contains("/portal/") || loc0.contains("Login.do") || loc0.contains("Auth.do");
        out.println("[1] 探测 http://1.1.1.1/ → " + probe.code
                + (probe.location != null ? "  Location=" + shorten(probe.location, 160) : ""));
        if (!intercepted) {
            out.println("结果：未被门户拦截（HTTP " + probe.code + "），无需认证 ✓");
            return;
        }
        if (probe.location == null) {
            out.println("结果：没拿到门户地址，认证失败 ✗");
            return;
        }

        // Login.do 返回的是「Success + JS 跳 Auth.do」的过渡页，直接按门户自己的走法请求 Auth.do
        String authUrl = probe.location.replace("/portal/Login.do", "/portal/Auth.do");
        if (authUrl.equals(probe.location)) {
            authUrl = probe.location;
        }
        authUrl += (authUrl.contains("?") ? "&" : "?") + "osType=Android";
        Resp page = request("GET", authUrl, null, 5);
        out.println("[2] 打开门户认证页 → " + page.code + " 最终URL=" + shorten(page.finalUrl, 220));
        java.util.regex.Matcher m =
                java.util.regex.Pattern.compile("[?&]token=([A-Za-z0-9%+/=_\\-]+)").matcher(page.finalUrl);
        String token = m.find() ? m.group(1) : null;
        if (token == null) {
            Resp page2 = request("GET", probe.location, null, 5);
            out.println("    （Login.do 直取 → " + page2.code + "）");
            m = java.util.regex.Pattern.compile("[?&]token=([A-Za-z0-9%+/=_\\-]+)").matcher(page2.finalUrl);
            token = m.find() ? m.group(1) : null;
        }
        if (token == null) {
            out.println("结果：门户页里没取到 token，认证失败 ✗");
            return;
        }
        out.println("    token=" + shorten(token, 60));

        String base = "http://" + hostOf(probe.location) + "/portal/Auth.do";
        // 门户 JS 会把 URL 里的网关参数（wlanuserip/wlanacname/nasid…）一并回传，这里照做
        String gw = probe.location.contains("?") ? probe.location.substring(probe.location.indexOf('?') + 1) : "";
        StringBuilder sb = new StringBuilder();
        sb.append("siteid=1&");     // 门户 JS: e.extend({method:i, siteid:r.SITE_ID}, a)，SITE_ID=1
        for (String kv : gw.split("&")) {
            if (kv.isEmpty() || kv.startsWith("token=") || kv.startsWith("_t=")) {
                continue;
            }
            sb.append(kv).append('&');
        }
        if ("free".equals(mode)) {
            sb.append("method=doAuthFree&token=").append(token);
        } else if ("noper".equals(mode)) {
            sb.append("method=doAuthNoper&token=").append(token);
        } else {
            sb.append("method=doAuth&account=").append(enc(account))
              .append("&paswd=").append(enc(password))
              .append("&token=").append(token);
        }
        String body = sb.toString();
        Resp auth = request("POST", base, body, 0);
        out.println("[3] POST " + base + "  方式=" + mode + " → " + auth.code);
        out.println("     响应：" + shorten(auth.body.replaceAll("\\s+", " "), 400));

        Resp verify = request("GET", "http://1.1.1.1/", null, 0);
        boolean codeOk = auth.body != null && auth.body.contains("\"code\":\"0\"");
        String vloc = verify.location == null ? "" : verify.location;
        boolean stillPortal = vloc.contains("/portal/") || vloc.contains("Login.do");
        boolean ok = codeOk || !stillPortal;
        out.println("[4] 复核 http://1.1.1.1/ → " + verify.code
                + (verify.location != null ? "  Location=" + shorten(verify.location, 120) : ""));
        out.println("结果：" + (ok ? "门户认证成功 ✓ 已能上网" : "门户认证失败 ✗ 仍被拦截")
                + "（服务端 code=" + (codeOk ? "0/NO_ERROR" : shorten(auth.body, 120)) + "）");
    }

    private static String hostOf(String url) {
        try {
            return new java.net.URL(url).getHost();
        } catch (Throwable t) {
            return "100.100.1.32";
        }
    }

    private static String enc(String s) {
        try {
            return java.net.URLEncoder.encode(s, "UTF-8");
        } catch (Throwable t) {
            return s;
        }
    }

    private static String shorten(String s, int n) {
        if (s == null) {
            return "null";
        }
        return s.length() <= n ? s : s.substring(0, n) + "…";
    }

    /** 用无障碍的滚动动作翻页（不需要坐标手势能力位） */
    private void scroll(int direction, int times) throws Exception {
        for (int i = 0; i < times; i++) {
            Object root = call(ua, "getRootInActiveWindow");
            if (root == null) {
                out.println("scroll: root == null");
                return;
            }
            List<Object> all = new ArrayList<Object>();
            collect(root, all, 0);
            Object target = null;
            int bestArea = -1;
            for (Object n : all) {
                if (!Boolean.TRUE.equals(call(n, "isScrollable"))) {
                    continue;
                }
                int area = area(n);
                if (area > bestArea) {
                    bestArea = area;
                    target = n;
                }
            }
            if (target == null) {
                out.println("scroll: 没找到可滚动节点");
                return;
            }
            out.println("scroll ok=" + call(target, "performAction", Integer.valueOf(direction))
                    + " node=" + describe(target));
            Thread.sleep(900);
        }
    }

    private int area(Object n) throws Exception {
        Object rect = Class.forName("android.graphics.Rect").getDeclaredConstructor().newInstance();
        call(n, "getBoundsInScreen", rect);
        int w = (Integer) field(rect, "right") - (Integer) field(rect, "left");
        int h = (Integer) field(rect, "bottom") - (Integer) field(rect, "top");
        return w * h;
    }

    /** 按屏幕坐标找最深节点并做无障碍点击（替代被 ROM 封掉的坐标手势） */
    private void clickAt(int x, int y) throws Exception {
        Object root = call(ua, "getRootInActiveWindow");
        if (root == null) {
            out.println("click-xy: root == null");
            return;
        }
        List<Object> all = new ArrayList<Object>();
        collect(root, all, 0);
        Object best = null;
        int bestArea = Integer.MAX_VALUE;
        for (Object n : all) {
            if (!contains(n, x, y)) {
                continue;
            }
            int a = area(n);
            if (a < bestArea) {
                bestArea = a;
                best = n;
            }
        }
        if (best == null) {
            out.println("click-xy: (" + x + "," + y + ") 没有节点");
            return;
        }
        out.println("click-xy 命中 " + describe(best));
        click(best, false);
    }

    private boolean contains(Object n, int x, int y) throws Exception {
        Object rect = Class.forName("android.graphics.Rect").getDeclaredConstructor().newInstance();
        call(n, "getBoundsInScreen", rect);
        return x >= (Integer) field(rect, "left") && x <= (Integer) field(rect, "right")
                && y >= (Integer) field(rect, "top") && y <= (Integer) field(rect, "bottom");
    }

    private String shell(String cmd) {
        try {
            // executeShellCommand 不做 shell 解析，这里显式套一层 sh -c
            Object pfd = call(ua, "executeShellCommand", "sh -c " + quote(cmd));
            Object fd = call(pfd, "getFileDescriptor");   // ParcelFileDescriptor → FileDescriptor
            FileInputStream in = new FileInputStream((java.io.FileDescriptor) fd);
            byte[] buf = new byte[8192];
            StringBuilder sb = new StringBuilder();
            int n;
            while ((n = in.read(buf)) > 0) {
                sb.append(new String(buf, 0, n));
            }
            in.close();
            return sb.toString().trim();
        } catch (Throwable t) {
            return "ERR " + t;
        }
    }

    private static String quote(String s) {
        return "'" + s.replace("'", "'\\''") + "'";
    }

    // ---------------- 反射工具 ----------------

    private static Object call(Object target, String name, Object... args) throws Exception {
        Method best = null;
        for (Method m : target.getClass().getMethods()) {
            if (!m.getName().equals(name) || m.getParameterCount() != args.length) {
                continue;
            }
            Class<?>[] ps = m.getParameterTypes();
            boolean ok = true;
            for (int i = 0; i < ps.length; i++) {
                if (args[i] == null) {
                    if (ps[i].isPrimitive()) {
                        ok = false;
                        break;
                    }
                    continue;
                }
                if (!box(ps[i]).isInstance(args[i])) {
                    ok = false;
                    break;
                }
            }
            if (ok) {
                best = m;
                break;
            }
        }
        if (best == null) {
            throw new NoSuchMethodException(name + "/" + args.length + " on " + target.getClass().getName());
        }
        best.setAccessible(true);
        return best.invoke(target, args);
    }

    private static Class<?> box(Class<?> p) {
        if (!p.isPrimitive()) return p;
        if (p == int.class) return Integer.class;
        if (p == long.class) return Long.class;
        if (p == float.class) return Float.class;
        if (p == boolean.class) return Boolean.class;
        if (p == double.class) return Double.class;
        if (p == short.class) return Short.class;
        if (p == byte.class) return Byte.class;
        if (p == char.class) return Character.class;
        return p;
    }

    private static Object field(Object o, String name) throws Exception {
        Field f = o.getClass().getField(name);
        return f.get(o);
    }

    private static float f(String s) {
        return Float.parseFloat(s);
    }

    private static String s(Object o) {
        return o == null ? null : o.toString();
    }

    private static String shortName(String cls) {
        if (cls == null) return "?";
        int i = cls.lastIndexOf('.');
        return i >= 0 ? cls.substring(i + 1) : cls;
    }

    private static List<String> readLines(String path) throws Exception {
        List<String> list = new ArrayList<String>();
        File file = new File(path);
        if (!file.exists()) return list;
        BufferedReader br = new BufferedReader(new FileReader(file));
        String l;
        while ((l = br.readLine()) != null) list.add(l);
        br.close();
        return list;
    }

    /** 支持双引号包参数的分词 */
    private static String[] split(String s) {
        List<String> parts = new ArrayList<String>();
        StringBuilder cur = new StringBuilder();
        boolean q = false;
        for (int i = 0; i < s.length(); i++) {
            char ch = s.charAt(i);
            if (ch == '"') {
                q = !q;
            } else if (!q && ch == ' ') {
                if (cur.length() > 0) {
                    parts.add(cur.toString());
                    cur.setLength(0);
                }
            } else {
                cur.append(ch);
            }
        }
        if (cur.length() > 0) parts.add(cur.toString());
        return parts.toArray(new String[0]);
    }
}
