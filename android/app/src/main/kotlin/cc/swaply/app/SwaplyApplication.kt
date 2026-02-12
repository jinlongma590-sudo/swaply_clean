package cc.swaply.app

import android.app.Application
import com.facebook.FacebookSdk
import com.facebook.appevents.AppEventsLogger

class SwaplyApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        // 初始化 Facebook SDK
        try {
            FacebookSdk.sdkInitialize(applicationContext)
            AppEventsLogger.activateApp(this)
            println("[SwaplyApplication] ✅ Facebook SDK initialized")
        } catch (e: Exception) {
            println("[SwaplyApplication] ❌ Facebook SDK init failed: ${e.message}")
        }
    }
}
