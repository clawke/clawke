import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load signing properties from key.properties (gitignored)
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val stripReleaseIntegrationTestPlugin by tasks.registering {
    val registrant = layout.projectDirectory.file(
        "src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java"
    )
    inputs.file(registrant).optional()
    outputs.upToDateWhen { false }
    doLast {
        val file = registrant.asFile
        if (!file.exists()) {
            return@doLast
        }
        val source = file.readText()
        val keptLines = mutableListOf<String>()
        var skippingIntegrationTest = false
        source.lineSequence().forEach { line ->
            if (line.contains("new dev.flutter.plugins.integration_test.IntegrationTestPlugin()")) {
                if (keptLines.lastOrNull()?.trim() == "try {") {
                    keptLines.removeAt(keptLines.lastIndex)
                }
                skippingIntegrationTest = true
                return@forEach
            }
            if (skippingIntegrationTest) {
                if (line.trim() == "}") {
                    skippingIntegrationTest = false
                }
                return@forEach
            }
            keptLines.add(line)
        }
        val stripped = keptLines.joinToString(System.lineSeparator()) +
            if (source.endsWith(System.lineSeparator())) System.lineSeparator() else ""
        if (stripped != source) {
            file.writeText(stripped)
        }
    }
}

android {
    namespace = "ai.clawke.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "ai.clawke.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // Fallback: debug signing for open source contributors
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation(platform("com.google.firebase:firebase-bom:34.6.0"))
    implementation("com.google.firebase:firebase-messaging")
}

flutter {
    source = "../.."
}

tasks.matching { it.name == "compileReleaseJavaWithJavac" }.configureEach {
    dependsOn(stripReleaseIntegrationTestPlugin)
}

tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(stripReleaseIntegrationTestPlugin)
}
