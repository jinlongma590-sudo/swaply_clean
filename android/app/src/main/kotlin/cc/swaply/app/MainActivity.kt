package cc.swaply.app

import android.content.Intent
import android.os.Bundle
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyEdgeToEdge()
    }

    // ✅ 保存状态（保留你原来的逻辑）
    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
    }

    // ✅ 恢复状态（保留你原来的逻辑）
    override fun onRestoreInstanceState(savedInstanceState: Bundle) {
        super.onRestoreInstanceState(savedInstanceState)
    }

    // ✅ 恢复 UI（每次回到前台都重新应用一次）
    override fun onResume() {
        super.onResume()
        applyEdgeToEdge()
    }

    // ✅ 处理新的 Intent（deeplink/notification）
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    private fun applyEdgeToEdge() {
        // ✅ 现代写法：让内容可以绘制到状态栏/导航栏下方（替代 systemUiVisibility）
        WindowCompat.setDecorFitsSystemWindows(window, false)

        // ✅ 不强制隐藏系统栏，只是允许“铺到系统栏下面”
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller.show(WindowInsetsCompat.Type.systemBars())
    }
}
