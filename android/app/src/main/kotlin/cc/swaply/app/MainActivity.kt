package cc.swaply.app

import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import androidx.core.splashscreen.SplashScreen
class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        // ✅ 【关键修复】必须在 super.onCreate() 之前确保 Intent 正确！
        // 确保来自通知的 Intent 被转换为 ACTION_VIEW + 深链 URI
        // 这样 SplashScreen API 才能看到正确的 Intent 并显示 Logo
        normalizeIntentForSplashScreen()

        // ✅ 【时序优化】给系统 SplashScreen API 一点时间处理 Intent
        // 特别是 Android 12+ 需要时间基于正确的 Intent 初始化 SplashScreen
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            Log.i(TAG, "⏱️ Android 12+ detected, adding small delay for SplashScreen initialization...")
            SystemClock.sleep(50) // 50ms 延迟，确保系统 SplashScreen 看到正确的 Intent
            Log.i(TAG, "✅ Delay completed, proceeding to super.onCreate()")
        }

        super.onCreate(savedInstanceState)

        // ✅ 记录日志用于调试
        logIntentDetails("onCreate", intent)

        // Log system level splash behavior (whether Android system triggers it)
        checkSplashScreenTriggered("onCreate")

        applyEdgeToEdge()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
    }

    override fun onRestoreInstanceState(savedInstanceState: Bundle) {
        super.onRestoreInstanceState(savedInstanceState)
    }

    override fun onResume() {
        super.onResume()
        applyEdgeToEdge()
    }

    override fun onNewIntent(intent: Intent) {
        // ✅ 在 super.onNewIntent() 之前转换 Intent（热启动场景）
        // 创建副本以避免修改原始 Intent
        val normalizedIntent = Intent(intent)
        val modified = normalizeIntentForSplashScreen(normalizedIntent)
        
        super.onNewIntent(normalizedIntent)

        // ✅ 记录日志用于调试
        logIntentDetails("onNewIntent", normalizedIntent)

        // Log system level splash behavior (whether Android system triggers it)
        checkSplashScreenTriggered("onNewIntent")

        setIntent(normalizedIntent)
    }

    private fun applyEdgeToEdge() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller.show(WindowInsetsCompat.Type.systemBars())
    }

    /**
     * ✅ 详细输出 Intent 信息用于调试
     */
    private fun logIntentDetails(source: String, intent: Intent?) {
        Log.i(TAG, "========================================")
        Log.i(TAG, "[$source] Intent Details:")
        Log.i(TAG, "========================================")

        if (intent == null) {
            Log.i(TAG, "Intent is NULL")
            Log.i(TAG, "========================================")
            return
        }

        // 1. Intent Action（关键！）
        Log.i(TAG, "Action: ${intent.action ?: "NULL"}")

        // 2. Intent Data（深链 URI）
        Log.i(TAG, "Data: ${intent.data ?: "NULL"}")

        // 3. Intent Categories
        val categories = intent.categories
        if (categories != null && categories.isNotEmpty()) {
            Log.i(TAG, "Categories: ${categories.joinToString(", ")}")
        } else {
            Log.i(TAG, "Categories: NULL")
        }

        // 4. Intent Flags
        Log.i(TAG, "Flags: 0x${Integer.toHexString(intent.flags)}")
        Log.i(TAG, "Flags详解:")
        logFlagDetails(intent.flags)

        // 5. Intent Component
        Log.i(TAG, "Component: ${intent.component}")

        // 6. Intent Package
        Log.i(TAG, "Package: ${intent.`package` ?: "NULL"}")

        // 7. Extras（推送通知的数据）
        val extras = intent.extras
        if (extras != null && !extras.isEmpty) {
            Log.i(TAG, "Extras:")
            for (key in extras.keySet()) {
                val value = extras.get(key)
                Log.i(TAG, "  - $key: $value")
            }
        } else {
            Log.i(TAG, "Extras: NULL or Empty")
        }

        // 8. 是否是 Task Root（冷启动标识）
        Log.i(TAG, "isTaskRoot: $isTaskRoot")

        // 9. Intent 类型判断
        when (intent.action) {
            Intent.ACTION_VIEW -> Log.i(TAG, "✅ Type: DEEP LINK (ACTION_VIEW)")
            Intent.ACTION_MAIN -> Log.i(TAG, "✅ Type: MANUAL LAUNCH (ACTION_MAIN)")
            else -> Log.i(TAG, "⚠️ Type: Unknown (${intent.action})")
        }

        Log.i(TAG, "========================================")
    }

    /**
     * ✅ 详细解析 Intent Flags
     */
    private fun logFlagDetails(flags: Int) {
        val flagsList = mutableListOf<String>()

        if (flags and Intent.FLAG_ACTIVITY_NEW_TASK != 0)
            flagsList.add("FLAG_ACTIVITY_NEW_TASK")
        if (flags and Intent.FLAG_ACTIVITY_CLEAR_TOP != 0)
            flagsList.add("FLAG_ACTIVITY_CLEAR_TOP")
        if (flags and Intent.FLAG_ACTIVITY_SINGLE_TOP != 0)
            flagsList.add("FLAG_ACTIVITY_SINGLE_TOP")
        if (flags and Intent.FLAG_ACTIVITY_CLEAR_TASK != 0)
            flagsList.add("FLAG_ACTIVITY_CLEAR_TASK")
        if (flags and Intent.FLAG_ACTIVITY_NO_ANIMATION != 0)
            flagsList.add("FLAG_ACTIVITY_NO_ANIMATION")
        if (flags and Intent.FLAG_ACTIVITY_REORDER_TO_FRONT != 0)
            flagsList.add("FLAG_ACTIVITY_REORDER_TO_FRONT")
        if (flags and Intent.FLAG_ACTIVITY_BROUGHT_TO_FRONT != 0)
            flagsList.add("FLAG_ACTIVITY_BROUGHT_TO_FRONT")

        if (flagsList.isEmpty()) {
            Log.i(TAG, "  - No special flags")
        } else {
            flagsList.forEach { flag ->
                Log.i(TAG, "  - $flag")
            }
        }
    }

    /**
     * ✅ 确保 Intent 在 SplashScreen 初始化前被正确设置
     * 关键：在 super.onCreate() 之前调用，确保系统 SplashScreen 看到正确的 Intent
     */
    private fun normalizeIntentForSplashScreen() {
        val modified = normalizeIntentForSplashScreen(intent)
        if (modified) {
            setIntent(intent)
        }
    }
    
    /**
     * ✅ 重载版本：处理传入的 Intent
     * @return 如果 Intent 被修改返回 true，否则返回 false
     */
    private fun normalizeIntentForSplashScreen(targetIntent: Intent?): Boolean {
        if (targetIntent == null) {
            Log.i(TAG, "⚠️ normalizeIntentForSplashScreen: Intent is null")
            return false
        }

        Log.i(TAG, "========================================")
        Log.i(TAG, "🔄 normalizeIntentForSplashScreen(targetIntent)")
        Log.i(TAG, "========================================")
        
        // 记录原始状态
        Log.i(TAG, "原始 Action: ${targetIntent.action ?: "NULL"}")
        Log.i(TAG, "原始 Data: ${targetIntent.data ?: "NULL"}")
        Log.i(TAG, "原始 Flags: 0x${Integer.toHexString(targetIntent.flags)}")

        var modified = false
        
        // 1. 检查是否是来自通知的 Intent（包含 payload 或 google.message_id）
        val hasPayload = targetIntent.getStringExtra("payload") != null
        val hasGoogleMessageId = targetIntent.extras?.containsKey("google.message_id") == true
        
        Log.i(TAG, "来自通知检查: hasPayload=$hasPayload, hasGoogleMessageId=$hasGoogleMessageId")
        
        if (hasPayload || hasGoogleMessageId) {
            // 来自通知的 Intent 需要确保是 ACTION_VIEW 且有 data URI
            
            // 如果有 payload 但没有 data URI，设置 data
            val payload = targetIntent.getStringExtra("payload")
            if (payload != null && payload.startsWith("swaply://") && targetIntent.data == null) {
                targetIntent.data = android.net.Uri.parse(payload)
                Log.i(TAG, "✅ 设置 Data URI: $payload")
                modified = true
            }
            
            // 确保 Action 是 ACTION_VIEW（通知启动应该被视为深链启动）
            if (targetIntent.action != Intent.ACTION_VIEW) {
                Log.i(TAG, "✅ 转换 Action: ${targetIntent.action} → ACTION_VIEW")
                targetIntent.action = Intent.ACTION_VIEW
                modified = true
            }
            
            // 确保有 BROWSABLE category（深链标准）
            val hasBrowsableCategory = targetIntent.categories?.contains(Intent.CATEGORY_BROWSABLE) ?: false
            if (!hasBrowsableCategory) {
                targetIntent.addCategory(Intent.CATEGORY_BROWSABLE)
                Log.i(TAG, "✅ 添加 CATEGORY_BROWSABLE")
                modified = true
            }
            
            // 清理可能干扰 SplashScreen 的 flags
            // FLAG_ACTIVITY_CLEAR_TOP 在某些情况下可能影响 SplashScreen 显示
            if (targetIntent.flags and Intent.FLAG_ACTIVITY_CLEAR_TOP != 0) {
                targetIntent.flags = targetIntent.flags and Intent.FLAG_ACTIVITY_CLEAR_TOP.inv()
                Log.i(TAG, "✅ 移除 FLAG_ACTIVITY_CLEAR_TOP")
                modified = true
            }
            
            // 确保有 NEW_TASK flag（通知启动需要）
            if (targetIntent.flags and Intent.FLAG_ACTIVITY_NEW_TASK == 0) {
                targetIntent.flags = targetIntent.flags or Intent.FLAG_ACTIVITY_NEW_TASK
                Log.i(TAG, "✅ 添加 FLAG_ACTIVITY_NEW_TASK")
                modified = true
            }
        }
        
        // 2. 记录最终状态
        Log.i(TAG, "最终 Action: ${targetIntent.action ?: "NULL"}")
        Log.i(TAG, "最终 Data: ${targetIntent.data ?: "NULL"}")
        Log.i(TAG, "最终 Flags: 0x${Integer.toHexString(targetIntent.flags)}")
        Log.i(TAG, "是否修改: $modified")
        Log.i(TAG, "========================================")
        
        // 注意：这个方法不调用 setIntent()，调用者负责设置修改后的 Intent
        // 返回修改状态供调用者判断
        return modified
    }

    /**
     * ✅ 检查是否触发了系统的 Splash Screen API
     */
    private fun checkSplashScreenTriggered(source: String) {
        Log.i(TAG, "========================================")
        Log.i(TAG, "[$source] Checking if SplashScreen API triggered...")

        // 打印相关启动信息，检查是否显示了启动屏
        // 对于 Android 12+ (API 31+)，使用 SplashScreen API
        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                // Android 12+ 使用平台 SplashScreen API
                val splashScreen = getSplashScreen()
                if (splashScreen != null) {
                    Log.i(TAG, "✅ SplashScreen API triggered (Android 12+)")
                } else {
                    Log.i(TAG, "⚠️ SplashScreen API not available (Android 12+)")
                }
            } else {
                Log.i(TAG, "ℹ️ Android version ${android.os.Build.VERSION.SDK_INT} (<31), using fallback splash")
            }
        } catch (e: Exception) {
            Log.i(TAG, "⚠️ Error checking SplashScreen: ${e.message}")
        }

        Log.i(TAG, "========================================")
    }

    companion object {
        private const val TAG = "MainActivity"
    }
}
