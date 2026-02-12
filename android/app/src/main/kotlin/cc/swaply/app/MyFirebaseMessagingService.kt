package cc.swaply.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class MyFirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)

        Log.d(TAG, "========================================")
        Log.d(TAG, "🔔 FCM 消息接收")
        Log.d(TAG, "========================================")

        // ✅ 获取数据
        val title = message.data["title"] ?: "Swaply"
        val body = message.data["body"] ?: ""
        val payload = message.data["payload"] ?: ""
        val notificationId = message.data["notification_id"]?.toIntOrNull() ?:
        System.currentTimeMillis().toInt()

        Log.d(TAG, "📦 Title: $title")
        Log.d(TAG, "📦 Body: $body")
        Log.d(TAG, "📦 Payload: $payload")
        Log.d(TAG, "📦 Notification ID: $notificationId")

        if (payload.isEmpty() || !payload.startsWith("swaply://")) {
            Log.w(TAG, "⚠️ Payload 无效或为空，不显示通知")
            Log.d(TAG, "========================================")
            return
        }

        // ✅ 创建并显示本地通知
        showNotification(title, body, payload, notificationId)

        Log.d(TAG, "========================================")
    }

    private fun showNotification(
        title: String,
        body: String,
        payload: String,
        notificationId: Int
    ) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // 1. 创建通知渠道（Android 8.0+）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Swaply Notifications",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Important notifications from Swaply"
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(channel)
            Log.d(TAG, "✅ 通知渠道已创建/更新")
        }

        // 2. ✅✅✅ 【方案1：完全模拟深链启动的Intent创建方式】
        Log.d(TAG, "========================================")
        Log.d(TAG, "🔧 创建通知Intent（方案1：完全模拟深链启动）")
        Log.d(TAG, "========================================")

        val intent = Intent(Intent.ACTION_VIEW).apply {
            data = Uri.parse(payload)  // ✅ 设置深链 URI

            // ✅✅✅ 【关键修改1】使用与深链启动完全相同的 flags
            // CLEAR_TASK 而不是 CLEAR_TOP：确保完整的冷启动流程
            // 这让通知启动的行为与浏览器深链启动完全一致
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK

            // ✅✅✅ 【方案2核心修复】使用 NotificationActivity 而不是 MainActivity
            // NotificationActivity 是一个 Activity Alias，launchMode=standard
            // 这强制系统创建新的实例，走完整的冷启动流程，显示完整的 SplashScreen
            component = ComponentName(packageName, "$packageName.NotificationActivity")

            // ✅✅✅ 【关键修改3】添加所有深链相关的 categories
            // BROWSABLE 和 DEFAULT 都是深链标准所需的
            addCategory(Intent.CATEGORY_BROWSABLE)
            addCategory(Intent.CATEGORY_DEFAULT)

            // ✅ 把 payload 也放到 extras，作为备份
            putExtra("payload", payload)
        }

        // 详细日志：记录Intent的所有关键属性
        Log.d(TAG, "📋 Intent 详细配置：")
        Log.d(TAG, "   Action: ${intent.action}")
        Log.d(TAG, "   Data URI: ${intent.data}")
        Log.d(TAG, "   Component: ${intent.component}")
        Log.d(TAG, "   ✅ 使用 NotificationActivity Alias (launchMode=standard)")
        Log.d(TAG, "   Package: ${intent.`package`}")
        Log.d(TAG, "   Flags (Binary): ${Integer.toBinaryString(intent.flags)}")
        Log.d(TAG, "   Flags (Hex): 0x${Integer.toHexString(intent.flags)}")
        Log.d(TAG, "   Categories: ${intent.categories}")
        Log.d(TAG, "   Has NEW_TASK: ${(intent.flags and Intent.FLAG_ACTIVITY_NEW_TASK) != 0}")
        Log.d(TAG, "   Has CLEAR_TASK: ${(intent.flags and Intent.FLAG_ACTIVITY_CLEAR_TASK) != 0}")
        Log.d(TAG, "   Has CLEAR_TOP: ${(intent.flags and Intent.FLAG_ACTIVITY_CLEAR_TOP) != 0}")

        // ✅✅✅ 【关键修改4】PendingIntent flags 使用 FLAG_IMMUTABLE
        // Android 12+ 强制要求使用 FLAG_IMMUTABLE 或 FLAG_MUTABLE
        // FLAG_ONE_SHOT 确保每次通知点击都创建新的启动实例
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_ONE_SHOT
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            notificationId,  // 使用唯一ID，避免Intent复用
            intent,
            pendingIntentFlags
        )

        Log.d(TAG, "✅ PendingIntent 已创建")
        Log.d(TAG, "   PendingIntent Flags: 0x${Integer.toHexString(pendingIntentFlags)}")
        Log.d(TAG, "   Request Code: $notificationId")
        Log.d(TAG, "")
        Log.d(TAG, "🎯 【方案2】通知启动预期行为：")
        Log.d(TAG, "   1. 系统查找 NotificationActivity Alias")
        Log.d(TAG, "   2. 发现 launchMode=standard，强制创建新实例")
        Log.d(TAG, "   3. target 指向 MainActivity，实际启动 MainActivity")
        Log.d(TAG, "   4. 因为是新实例，触发完整的冷启动流程")
        Log.d(TAG, "   5. 系统 SplashScreen 显示完整 Logo（背景+图标）")
        Log.d(TAG, "========================================")

        // 3. 构建通知
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)  // ✅ 使用应用图标
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)  // ✅ 点击后自动消失
            .setContentIntent(pendingIntent)  // ✅ 使用我们的 ACTION_VIEW Intent
            .build()

        // 4. 显示通知
        notificationManager.notify(notificationId, notification)
        Log.d(TAG, "✅ 本地通知已显示 (ID: $notificationId)")
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "🔑 FCM Token 刷新: ${token.take(20)}...")
        // Flutter 层会自动处理 token 刷新
    }

    companion object {
        private const val TAG = "MyFCMService"
        private const val CHANNEL_ID = "swaply_high_importance"
    }
}