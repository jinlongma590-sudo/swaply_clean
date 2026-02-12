package cc.swaply.app

import android.app.ActivityManager
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    private var iconBitmap: Bitmap? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // 第1次设置：在 super.onCreate() 之前
        setTaskDescriptionWithIcon("onCreate-before")

        // 确保来自通知的 Intent 被转换为 ACTION_VIEW + 深链 URI
        normalizeIntentForSplashScreen()

        // 给系统 SplashScreen API 一点时间处理 Intent
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            Log.i(TAG, "⏱️ Android 12+ detected, adding small delay for SplashScreen initialization...")
            SystemClock.sleep(50)
            Log.i(TAG, "✅ Delay completed, proceeding to super.onCreate()")
        }

        super.onCreate(savedInstanceState)

        // 记录日志用于调试
        logIntentDetails("onCreate", intent)

        // Log system level splash behavior
        checkSplashScreenTriggered("onCreate")

        applyEdgeToEdge()
    }

    override fun onPostCreate(savedInstanceState: Bundle?) {
        super.onPostCreate(savedInstanceState)
        // 第2次设置：在 onPostCreate() 中
        setTaskDescriptionWithIcon("onPostCreate")
    }

    override fun onResume() {
        super.onResume()
        // 第3次设置：在 onResume() 中
        setTaskDescriptionWithIcon("onResume")
        applyEdgeToEdge()
    }

    override fun onPostResume() {
        super.onPostResume()
        // 第4次设置：在 onPostResume() 中
        setTaskDescriptionWithIcon("onPostResume")
    }

    override fun onNewIntent(intent: Intent) {
        // 第5次设置：在 onNewIntent() 之前
        setTaskDescriptionWithIcon("onNewIntent-before")

        val normalizedIntent = Intent(intent)
        val modified = normalizeIntentForSplashScreen(normalizedIntent)

        super.onNewIntent(normalizedIntent)

        // 记录日志用于调试
        logIntentDetails("onNewIntent", normalizedIntent)

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
     * 设置 Recent Apps 中的任务描述，使用缓存的 Bitmap 避免重复加载
     * 使用新旧 API 确保兼容性
     */
    private fun setTaskDescriptionWithIcon(source: String) {
        try {
            Log.i(TAG, "========================================")
            Log.i(TAG, "🎨 [$source] 设置 TaskDescription（Recent Apps Logo）")
            Log.i(TAG, "========================================")

            val label = getString(R.string.app_name)
            Log.i(TAG, "Label: $label")
            Log.i(TAG, "Android SDK: ${Build.VERSION.SDK_INT}")

            // 使用资源ID加载图标
            val iconResId = R.mipmap.ic_launcher

            // ✅【关键修复】统一使用兼容的 TaskDescription 构造函数 (API 21+)
            // 避免使用 TaskDescription.Builder (API 28+) 在某些设备上可能不可用
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) { // API 21+
                try {
                    Log.i(TAG, "🔧 使用兼容 API: TaskDescription constructor (Android 5.0+, API 21+)")
                    @Suppress("DEPRECATION")
                    setTaskDescription(ActivityManager.TaskDescription(label, iconResId)) // 使用资源ID
                    Log.i(TAG, "✅ TaskDescription 设置成功")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ TaskDescription 设置失败: ${e.message}")
                    Log.e(TAG, "堆栈跟踪: ${e.stackTraceToString()}")
                }
            } else {
                Log.i(TAG, "🔧 Android 版本 < 5.0 (API <21)，跳过 TaskDescription 设置")
            }

        } catch (e: Exception) {
            Log.e(TAG, "========================================")
            Log.e(TAG, "❌ [$source] 设置 TaskDescription 失败", e)
            Log.e(TAG, "错误信息: ${e.message}")
            Log.e(TAG, "堆栈跟踪: ${e.stackTraceToString()}")
            Log.e(TAG, "========================================")
        }
    }

    /**
     * 加载应用图标（只加载一次，缓存使用）
     */
    private fun loadAppIcon(): Bitmap? {
        Log.i(TAG, "🔍 开始加载应用图标...")

        var icon: Bitmap? = null
        try {
            Log.i(TAG, "🔍 方法1: 尝试从 PackageManager 获取图标...")
            val drawable = packageManager.getApplicationIcon(applicationInfo)
            icon = drawableToBitmap(drawable)
            if (icon != null) {
                Log.i(TAG, "✅ 方法1成功: 从 PackageManager 获取到图标 (${icon.width}x${icon.height})")
                return icon
            } else {
                Log.w(TAG, "⚠️ 方法1失败: drawableToBitmap 返回 null")
            }
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ 方法1失败: ${e.message}")
        }

        try {
            Log.i(TAG, "🔍 方法2: 尝试从 resources 获取图标...")
            val drawable = resources.getDrawable(applicationInfo.icon, theme)
            icon = drawableToBitmap(drawable)
            if (icon != null) {
                Log.i(TAG, "✅ 方法2成功: 从 resources 获取到图标 (${icon.width}x${icon.height})")
                return icon
            } else {
                Log.w(TAG, "⚠️ 方法2失败: drawableToBitmap 返回 null")
            }
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ 方法2失败: ${e.message}")
        }

        try {
            Log.i(TAG, "🔍 方法3: 尝试使用 R.mipmap.ic_launcher...")
            val drawable = resources.getDrawable(R.mipmap.ic_launcher, theme)
            icon = drawableToBitmap(drawable)
            if (icon != null) {
                Log.i(TAG, "✅ 方法3成功: 从 R.mipmap.ic_launcher 获取到图标 (${icon.width}x${icon.height})")
                return icon
            } else {
                Log.w(TAG, "⚠️ 方法3失败: drawableToBitmap 返回 null")
            }
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ 方法3失败: ${e.message}")
        }

        Log.e(TAG, "❌ 所有方法都无法加载图标！")
        return null
    }

    /**
     * 将 Drawable 转换为 Bitmap
     */
    private fun drawableToBitmap(drawable: Drawable): Bitmap? {
        return try {
            // 如果已经是 BitmapDrawable，直接返回 bitmap
            if (drawable is BitmapDrawable) {
                Log.i(TAG, "   Drawable 是 BitmapDrawable，直接获取 bitmap")
                return drawable.bitmap
            }

            // 否则，创建一个新的 Bitmap 并绘制 Drawable
            val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 96
            val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 96

            Log.i(TAG, "   创建 Bitmap: ${width}x${height}")

            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)

            Log.i(TAG, "   Drawable 已绘制到 Bitmap")
            bitmap
        } catch (e: Exception) {
            Log.e(TAG, "   drawableToBitmap 失败: ${e.message}")
            null
        }
    }

    /**
     * 详细输出 Intent 信息用于调试
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

        Log.i(TAG, "Action: ${intent.action ?: "NULL"}")
        Log.i(TAG, "Data: ${intent.data ?: "NULL"}")

        val categories = intent.categories
        if (categories != null && categories.isNotEmpty()) {
            Log.i(TAG, "Categories: ${categories.joinToString(", ")}")
        } else {
            Log.i(TAG, "Categories: NULL")
        }

        Log.i(TAG, "Flags: 0x${Integer.toHexString(intent.flags)}")
        Log.i(TAG, "Flags详解:")
        logFlagDetails(intent.flags)

        Log.i(TAG, "Component: ${intent.component}")
        Log.i(TAG, "Package: ${intent.`package` ?: "NULL"}")

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

        Log.i(TAG, "isTaskRoot: $isTaskRoot")

        when (intent.action) {
            Intent.ACTION_VIEW -> Log.i(TAG, "✅ Type: DEEP LINK (ACTION_VIEW)")
            Intent.ACTION_MAIN -> Log.i(TAG, "✅ Type: MANUAL LAUNCH (ACTION_MAIN)")
            else -> Log.i(TAG, "⚠️ Type: Unknown (${intent.action})")
        }

        Log.i(TAG, "========================================")
    }

    /**
     * 详细解析 Intent Flags
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
     * 确保 Intent 在 SplashScreen 初始化前被正确设置
     */
    private fun normalizeIntentForSplashScreen() {
        val modified = normalizeIntentForSplashScreen(intent)
        if (modified) {
            setIntent(intent)
        }
    }

    /**
     * 重载版本：处理传入的 Intent
     */
    private fun normalizeIntentForSplashScreen(targetIntent: Intent?): Boolean {
        if (targetIntent == null) {
            Log.i(TAG, "⚠️ normalizeIntentForSplashScreen: Intent is null")
            return false
        }

        Log.i(TAG, "========================================")
        Log.i(TAG, "🔄 normalizeIntentForSplashScreen(targetIntent)")
        Log.i(TAG, "========================================")

        Log.i(TAG, "原始 Action: ${targetIntent.action ?: "NULL"}")
        Log.i(TAG, "原始 Data: ${targetIntent.data ?: "NULL"}")
        Log.i(TAG, "原始 Flags: 0x${Integer.toHexString(targetIntent.flags)}")

        var modified = false

        val hasPayload = targetIntent.getStringExtra("payload") != null
        val hasGoogleMessageId = targetIntent.extras?.containsKey("google.message_id") == true

        Log.i(TAG, "来自通知检查: hasPayload=$hasPayload, hasGoogleMessageId=$hasGoogleMessageId")

        if (hasPayload || hasGoogleMessageId) {
            val payload = targetIntent.getStringExtra("payload")
            if (payload != null && payload.startsWith("swaply://") && targetIntent.data == null) {
                targetIntent.data = android.net.Uri.parse(payload)
                Log.i(TAG, "✅ 设置 Data URI: $payload")
                modified = true
            }

            if (targetIntent.action != Intent.ACTION_VIEW) {
                Log.i(TAG, "✅ 转换 Action: ${targetIntent.action} → ACTION_VIEW")
                targetIntent.action = Intent.ACTION_VIEW
                modified = true
            }

            val hasBrowsableCategory = targetIntent.categories?.contains(Intent.CATEGORY_BROWSABLE) ?: false
            if (!hasBrowsableCategory) {
                targetIntent.addCategory(Intent.CATEGORY_BROWSABLE)
                Log.i(TAG, "✅ 添加 CATEGORY_BROWSABLE")
                modified = true
            }

            if (targetIntent.flags and Intent.FLAG_ACTIVITY_CLEAR_TOP != 0) {
                targetIntent.flags = targetIntent.flags and Intent.FLAG_ACTIVITY_CLEAR_TOP.inv()
                Log.i(TAG, "✅ 移除 FLAG_ACTIVITY_CLEAR_TOP")
                modified = true
            }

            if (targetIntent.flags and Intent.FLAG_ACTIVITY_NEW_TASK == 0) {
                targetIntent.flags = targetIntent.flags or Intent.FLAG_ACTIVITY_NEW_TASK
                Log.i(TAG, "✅ 添加 FLAG_ACTIVITY_NEW_TASK")
                modified = true
            }
        }

        Log.i(TAG, "最终 Action: ${targetIntent.action ?: "NULL"}")
        Log.i(TAG, "最终 Data: ${targetIntent.data ?: "NULL"}")
        Log.i(TAG, "最终 Flags: 0x${Integer.toHexString(targetIntent.flags)}")
        Log.i(TAG, "是否修改: $modified")
        Log.i(TAG, "========================================")

        return modified
    }

    /**
     * 检查是否触发了系统的 Splash Screen API
     */
    private fun checkSplashScreenTriggered(source: String) {
        Log.i(TAG, "========================================")
        Log.i(TAG, "[$source] Checking if SplashScreen API triggered...")

        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
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
