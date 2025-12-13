import java.util.Properties
import java.io.FileInputStream
import kotlin.math.max

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

// ✅ 读取签名配置
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// ✅ 关键：保证 Android 12+ SplashScreen API 所需的 SDK 版本足够高
// （避免 flutter.compileSdkVersion / flutter.targetSdkVersion 被你环境里某些配置拉低）
val resolvedCompileSdk = max(flutter.compileSdkVersion, 34)
val resolvedTargetSdk = max(flutter.targetSdkVersion, 34)
val resolvedMinSdk = max(flutter.minSdkVersion, 21)

android {
    namespace = "cc.swaply.app"
    compileSdk = resolvedCompileSdk
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "cc.swaply.app"
        minSdk = resolvedMinSdk
        targetSdk = resolvedTargetSdk
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ✅ 签名配置
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // ✅ 使用 release 签名
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // ✅ 关键修复：提供 Theme.SplashScreen / postSplashScreenTheme
    implementation("androidx.core:core-splashscreen:1.0.1")

    // ✅ Firebase（推送通知）
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
    implementation("com.google.firebase:firebase-messaging-ktx")
    implementation("com.google.firebase:firebase-analytics-ktx")

    // ✅ Facebook SDK - 修复 Facebook 登录问题
    implementation("com.facebook.android:facebook-android-sdk:16.0.0")
}

// ✅ 应用 Google Services 插件（必须在文件最后）
apply(plugin = "com.google.gms.google-services")