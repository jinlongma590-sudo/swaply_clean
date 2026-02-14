package cc.swaply.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * 蹦床 Activity (Trampoline)
 * 作用：作为一个透明的中转站，强制让系统以 Launcher 模式启动 MainActivity，
 * 从而确保 Android 12+ 的 Splash Screen Logo 能够显示。
 */
class NotificationTrampolineActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 1. 获取通知传递过来的所有数据 (payload, notification_id 等)
        val extras = intent.extras

        // 2. 构建真正要去往 MainActivity 的 Intent
        val mainIntent = Intent(this, MainActivity::class.java).apply {
            // ⭐⭐⭐ 核心伪装术 ⭐⭐⭐
            // 设置 Action 为 MAIN，Category 为 LAUNCHER
            // 这告诉 Android 系统：“我是从桌面图标点进来的！” -> 系统强制显示 Logo
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)

            // ⭐⭐⭐ 数据传递策略 ⭐⭐⭐
            // 绝对不要设置 data (Uri)！不要写 data = Uri.parse(...)
            // 所有的深链数据全部通过 extras 传递。
            // 你的 MainActivity 里的 normalizeIntentForSplashScreen 会负责读取 extras 并处理。
            if (extras != null) {
                putExtras(extras)
            }

            // Flags 配置：确保冷启动逻辑正确
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }

        // 3. 启动主页
        startActivity(mainIntent)

        // 4. 立即关闭当前页面，并不使用任何转场动画，让用户无感知
        overridePendingTransition(0, 0)
        finish()
    }
}
