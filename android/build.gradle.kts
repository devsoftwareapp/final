allprojects {
    repositories {
        google()
        mavenCentral()
        // 403 hatasını aşmak için alternatif depolar
        maven { url = uri("https://plugins.gradle.org/m2/") }
        maven { url = uri("https://repo.maven.apache.org/maven2/") }
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
    // Döngüsel bağımlılığı (Circular referencing) önlemek için kontrol
    if (project.name != "app") {
        evaluationDependsOn(":app")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
