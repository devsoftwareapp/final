allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://plugins.gradle.org/m2/") }
    }
}

rootProject.layout.buildDirectory = rootProject.layout.buildDirectory.dir("../../build").get()

subprojects {
    project.layout.buildDirectory = rootProject.layout.buildDirectory.dir(project.name).get()
}

subprojects {
    if (project.name != "app") {
        project.evaluationDependsOn(":app")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
