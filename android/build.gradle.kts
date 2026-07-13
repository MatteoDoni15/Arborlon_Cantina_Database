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

// Alcuni plugin (mobile_scanner, share_plus, network_info_plus, google_mlkit_*)
// dichiarano un compileSdk vecchio (34) incompatibile con le librerie Android
// recenti che richiedono almeno l'API 36: qui lo alziamo per tutti i moduli.
subprojects {
    val bumpCompileSdk: Project.() -> Unit = {
        extensions.findByType(com.android.build.api.dsl.CommonExtension::class.java)?.let { android ->
            if ((android.compileSdk ?: 0) < 36) {
                android.compileSdk = 36
            }
        }
    }
    // ":app" risulta già valutato a questo punto (per via di evaluationDependsOn
    // qui sopra), quindi afterEvaluate fallirebbe: in quel caso applichiamo subito.
    if (state.executed) bumpCompileSdk() else afterEvaluate { bumpCompileSdk() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
