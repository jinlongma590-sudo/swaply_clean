import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate, MessagingDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // ✅ 检查 GoogleService-Info.plist 是否存在
        if let plistPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") {
            print("✅ GoogleService-Info.plist 找到: \(plistPath)")

            // ✅ 1. Firebase 初始化
            FirebaseApp.configure()

            // ✅ 2. 设置 FCM 代理
            Messaging.messaging().delegate = self

            // ✅ 3. 设置通知代理
            if #available(iOS 10.0, *) {
                UNUserNotificationCenter.current().delegate = self

                // ✅ 4. 请求通知权限
                let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
                UNUserNotificationCenter.current().requestAuthorization(
                    options: authOptions,
                    completionHandler: { granted, error in
                        if granted {
                            print("✅ iOS 通知权限已授予")
                        } else if let error = error {
                            print("❌ iOS 通知权限请求失败: \(error.localizedDescription)")
                        } else {
                            print("⚠️ iOS 通知权限被拒绝")
                        }
                    }
                )
            }

            // ✅ 5. 注册远程通知
            application.registerForRemoteNotifications()
        } else {
            print("❌ GoogleService-Info.plist 未找到，跳过 Firebase 初始化")
            print("⚠️ 应用将在没有推送通知的情况下运行")
            // 不调用 Firebase，避免崩溃
        }

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // ✅ 6. 处理 APNS Token（设备令牌）
    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // 将 APNS Token 传递给 FCM
        Messaging.messaging().apnsToken = deviceToken

        // 打印 Token（调试用）
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("✅ APNS Token 已注册: \(token)")
    }

    // ✅ 7. 处理注册失败
    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ APNS Token 注册失败: \(error.localizedDescription)")
    }

    // ✅ 8. FCM Token 更新回调
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let token = fcmToken {
            print("✅ FCM Token (iOS): \(token)")

            // 将 Token 存储到 UserDefaults，Flutter 可以读取
            UserDefaults.standard.set(token, forKey: "fcm_token")

            // 可以通过 NotificationCenter 通知 Flutter
            NotificationCenter.default.post(
                name: NSNotification.Name("FCMTokenReceived"),
                object: nil,
                userInfo: ["token": token]
            )
        }
    }

    // ✅ 9. 接收远程通知（App 在前台时）
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        // 打印通知内容（调试用）
        print("🔔 收到前台通知")
        print("   标题: \(notification.request.content.title)")
        print("   内容: \(notification.request.content.body)")
        print("   数据: \(userInfo)")

        // iOS 14+ 显示横幅、播放声音、显示角标
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            // iOS 10-13 使用 .alert
            completionHandler([.alert, .sound, .badge])
        }
    }

    // ✅ 10. 用户点击通知
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        print("🔔 用户点击通知")
        print("   数据: \(userInfo)")

        // 提取深链数据
        if let payload = userInfo["payload"] as? String {
            print("   深链: \(payload)")
            // 可以通过 Method Channel 传递给 Flutter 处理深链跳转
        } else if let deepLink = userInfo["deep_link"] as? String {
            print("   深链: \(deepLink)")
        }

        completionHandler()
    }

    // ✅ 11. 处理静默推送（后台数据更新）
    override func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("🔔 收到远程通知（静默或后台）")
        print("   数据: \(userInfo)")

        // 如果有 FCM 消息数据
        if let messageID = userInfo["gcm.message_id"] as? String {
            print("   FCM Message ID: \(messageID)")
        }

        completionHandler(.newData)
    }

    // ========== ✅ 新增：深链处理逻辑 ==========

    // ✅ 12. 处理深链 - Universal Links (HTTPS)
    override func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = userActivity.webpageURL {
            print("✅ [DeepLink] Universal Link: \(url.absoluteString)")

            if url.host == "swaply.cc" || url.host == "www.swaply.cc" {
                if url.path.contains("auth/callback") || url.path.contains("login-callback") {
                    print("   → OAuth callback detected via Universal Link")
                }
            }

            return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
        }
        return false
    }

    // ✅ 13. 处理深链 - Custom URL Scheme
    override func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
    ) -> Bool {
        print("✅ [DeepLink] Custom URL Scheme: \(url.absoluteString)")

        if url.scheme == "cc.swaply.app" {
            print("   → OAuth callback detected")
            if url.host == "login-callback" {
                print("   → Login callback path")
            }
        } else if url.scheme?.contains("googleusercontent") == true {
            print("   → Google Sign-In callback detected")
        } else if url.scheme == "io.supabase.flutter" {
            print("   → Supabase callback detected")
        } else if url.scheme == "swaply" {
            print("   → Swaply custom scheme detected")
        }

        return super.application(app, open: url, options: options)
    }
}
