allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// 플러그인들이 오래된 compileSdk로 빌드되는 문제 방지 — 모든 서브프로젝트를 36으로 통일
subprojects {
    plugins.withId("com.android.library") {
        extensions.findByName("android")?.let { ext ->
            try {
                ext.javaClass.getMethod("setCompileSdkVersion", Int::class.javaPrimitiveType).invoke(ext, 36)
            } catch (_: Exception) {}
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
