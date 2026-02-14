package cc.swaply.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
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

        // 基础校验
        if (payload.isEmpty() || !payload.startsWith("swaply://")) {
            Log.w(TAG, "⚠️ Payload 无效或为空，不显示通知")
            Log.d(TAG, "========================================")
            return
        }

        // ✅ 传递完整的 data map 给处理函数
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
        }

        // 2. ✅✅✅ 【蹦床模式】指向 NotificationTrampolineActivity
        // 这里不需要设置 Action=MAIN 或 Category=LAUNCHER，因为这只是跳转到中间页
        // 关键是把数据通过 putExtra 带过去
        val intent = Intent(this, NotificationTrampolineActivity::class.java).apply {

            // ✅ 只传数据，不要 setUrl/setData，防止系统误判
            putExtra("payload", payload)
            putExtra("notification_id", notificationId.toString())

            // 传递所有原始数据
            dataMap.forEach { (key, value) ->
                putExtra(key, value)
            }

            // Flags
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }

        // PendingIntent Flags
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

        Log.d(TAG, "✅ PendingIntent 已创建 (目标: Trampoline)")

        // 3. 构建通知
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        // 4. 显示通知
        notificationManager.notify(notificationId, notification)
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "🔑 FCM Token 刷新")
    }

    companion object {
        private const val TAG = "MyFCMService"
        private const val CHANNEL_ID = "swaply_notifications"
    }
}
