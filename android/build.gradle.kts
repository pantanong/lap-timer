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
// Some plugins (e.g. flutter_blue_plus 1.34.x) are compiled against an old
// Android API level, but their AndroidX dependencies need at least 34.
// Raise compileSdk for plugin libraries (this does not change minSdk, so
// the devices the app runs on stay the same).
subprojects {
    plugins.withId("com.android.library") {
        val android = extensions.getByName("android")
        android.javaClass
            .getMethod("setCompileSdk", Integer::class.java)
            .invoke(android, 36)
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
