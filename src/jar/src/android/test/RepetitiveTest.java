package android.test;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * Android 12 把 android.test.RepetitiveTest 从 android.test.runner.jar 里删掉了，
 * 但 /system/framework/uiautomator.jar 的 TestCaseCollector 仍在引用它，
 * 于是官方 `uiautomator runtest` 会以
 *   Failed resolution of: Landroid/test/RepetitiveTest;
 * 崩掉。这里按 AOSP 原定义把它补回来，随我们的 jar 一起加载。
 */
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.METHOD)
public @interface RepetitiveTest {
    int numIterations() default 1;
}
