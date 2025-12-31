import com.android.build.gradle.BaseExtension
import org.gradle.api.tasks.Delete
import org.gradle.api.file.Directory

allprojects {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        maven { url = uri("https://jitpack.io") }
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
    afterEvaluate {
        if (project.name != "app") {
            project.evaluationDependsOn(":app")
        }
    }
}

/**
 * 🔴 ASIL ÇÖZÜM BURASI
 * android_intent_plus ve benzeri plugin'lerde eksik olan
 * compileSdk hatasını MERKEZDEN çözer
 */
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let {
            (it as BaseExtension).apply {
                compileSdkVersion(34)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
