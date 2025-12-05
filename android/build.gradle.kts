// android/build.gradle.kts  —— Kotlin DSL + 安全避免循环依赖

// ✅ 添加 buildscript 块以支持 Google Services 插件
buildscript {
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        // ✅ 添加 Google Services 插件（FCM 必需）
        classpath("com.google.gms:google-services:4.4.0")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// ✅ 用 File，而不是字符串；避免 layout.buildDirectory 的循环求值
rootProject.buildDir = file("../build")

subprojects {
    // 用 File(rootProject.buildDir, project.name) 组合路径
    project.buildDir = File(rootProject.buildDir, project.name)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.buildDir)
}