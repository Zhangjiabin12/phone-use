#!/bin/bash
# 编译 → dex → 打包 pu.jar（只依赖 JDK + r8.jar）
# 注意：src/ 里的类都进 jar；stubs/ 只用于编译，不进 jar
set -e
D=/opt/phone-use-jar
R8=$D/tools/r8.jar
[ -s "$R8" ] || { echo "缺 $R8"; exit 1; }

rm -rf "$D/classes" "$D/classes.dex" "$D/pu.jar"
mkdir -p "$D/classes"

find "$D/src" "$D/stubs" -name '*.java' > /tmp/pu-sources.txt
echo "== 源文件 =="; sed "s|$D/||" /tmp/pu-sources.txt
javac -nowarn --release 8 -d "$D/classes" @/tmp/pu-sources.txt

# D8 需要 stub 提供 UiAutomatorTestCase 父类
jar cf "$D/tools/stubs.jar" -C "$D/classes" com/android/uiautomator/testrunner/UiAutomatorTestCase.class

# 只 dex src 里的类（我们的测试类及其内部类 + 补回来的 android.test.RepetitiveTest）
# 注意：D8 不接受目录，必须显式列出所有 .class；内部类也要一起，否则 NoClassDefFoundError
mapfile -t FILES < <(find "$D/classes/com/dsh/phoneuse" "$D/classes/android/test" -name '*.class')
echo "== 参与 dex 的类：${#FILES[@]} 个 =="
java -cp "$R8" com.android.tools.r8.D8 --release --min-api 26 \
  --lib "$D/tools/stubs.jar" --output "$D" "${FILES[@]}"

rm -f "$D/pu.jar"
zip -0 -X -q -j "$D/pu.jar" "$D/classes.dex"
echo "== 产物 =="
unzip -v "$D/pu.jar" | tail -3
python3 /tmp/dex-classes.py "$D/pu.jar" 2>/dev/null | head -5 || true
