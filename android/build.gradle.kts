// android/build.gradle.kts  —— Kotlin DSL + 安全避免循环依赖

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
