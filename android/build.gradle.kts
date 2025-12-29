allprojects {
    repositories {
        google()
        mavenCentral()
        // Bazı durumlarda kütüphaneler gradle plugin sayfasından çekilemezse alternatif olarak ekliyoruz
        maven { url = uri("https://plugins.gradle.org/m2/") }
    }
}

// Build dizini ayarları
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
    // Proje değerlendirme bağımlılığını sadece gerekli olduğunda çalışacak şekilde güvenli hale getirelim
    afterEvaluate {
        if (project.hasProperty("android")) {
            project.evaluationDependsOn(":app")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
