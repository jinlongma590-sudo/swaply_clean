package cc.swaply.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
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

        // ✅ 创建并显示本地通知，传递完整的 data map
        showNotification(title, body, payload, notificationId, message.data)

        Log.d(TAG, "========================================")
    }

    private fun showNotification(
        title: String,
        body: String,
        payload: String,
        notificationId: Int,
        dataMap: Map<String, String>
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
            Log.d(TAG, "✅ 通知渠道已创建/更新: $CHANNEL_ID")
        }

        // 2. ✅✅✅ 【核心策略】创建隐式 Intent，让系统通过 intent-filter 匹配 MainActivity
        //
        // 为什么使用隐式 Intent？
        // - 系统会通过 AndroidManifest.xml 的 intent-filter 自动匹配 MainActivity
        // - 在匹配过程中，系统会正确加载 MainActivity 的所有元数据（icon, label 等）
        // - Recent Apps 会显示正确的应用图标
        //
        // 如果使用显式 Intent（setComponent）会导致：
        // - 系统跳过 intent-filter 匹配过程
        // - 可能不会完整加载 Activity 的元数据
        // - Recent Apps 可能显示默认图标（无 logo）
        val intent = Intent(Intent.ACTION_VIEW).apply {
            // ✅ 设置深链 URI
            data = Uri.parse(payload)

            // ✅ 限定在本应用内解析（防止其他应用处理）
            setPackage(packageName)

            // ✅ 添加必要的 categories（匹配 MainActivity 的 intent-filter）
            addCategory(Intent.CATEGORY_DEFAULT)
            addCategory(Intent.CATEGORY_BROWSABLE)

            // ✅✅✅ 【关键 Flags】
            // FLAG_ACTIVITY_NEW_TASK: 从非 Activity context 启动 Activity 时必须
            // FLAG_ACTIVITY_CLEAR_TOP: 如果 Activity 已存在，清除它上面的 Activity 栈
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)

            // ✅ 传递额外数据（作为备份）
            putExtra("payload", payload)
            putExtra("notification_id", notificationId.toString())

            // ✅ 传递所有原始数据
            dataMap.forEach { (key, value) ->
                putExtra(key, value)
            }
        }

        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            notificationId,
            intent,
            pendingIntentFlags
        )

        Log.d(TAG, "✅ PendingIntent 已创建（隐式 Intent）")
        Log.d(TAG, "   Action: ${intent.action}")
        Log.d(TAG, "   Data: ${intent.data}")
        Log.d(TAG, "   Package: ${intent.`package`}")
        Log.d(TAG, "   Categories: ${intent.categories}")
        Log.d(TAG, "   Flags: 0x${Integer.toHexString(intent.flags)}")
        Log.d(TAG, "   Component: ${intent.component} (应为 null，让系统自动匹配)")

        // 3. 构建通知
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)  // ✅ 使用应用图标
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)  // ✅ 点击后自动消失
            .setContentIntent(pendingIntent)  // ✅ 使用隐式 Intent 的 PendingIntent
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
        // ✅ 与 AndroidManifest.xml 中的 default_notification_channel_id 保持一致
        private const val CHANNEL_ID = "swaply_notifications"
    }
}