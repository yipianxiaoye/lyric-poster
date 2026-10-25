import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Keep signing material outside the source tree. The build script sets this
// variable, while Android Studio users may supply an ignored key.properties.
val signingPropertiesPath = System.getenv("LYRIC_POSTER_KEY_PROPERTIES")
val signingPropertiesFile = if (signingPropertiesPath.isNullOrBlank()) {
    rootProject.file("key.properties")
} else {
    file(signingPropertiesPath)
}
val signingProperties = Properties()
if (signingPropertiesFile.isFile) {
    signingPropertiesFile.inputStream().use { signingProperties.load(it) }
}
val releaseRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
// CI may explicitly request a disposable test signature. Published author APKs
// use the preserved private signing configuration so installed apps can update.
val allowDebugSigning = System.getenv("LYRIC_POSTER_ALLOW_DEBUG_SIGNING") == "true"
if (releaseRequested && !signingPropertiesFile.isFile && !allowDebugSigning) {
    throw GradleException(
        "Release signing is missing. Set LYRIC_POSTER_KEY_PROPERTIES or create android/key.properties. " +
            "See scripts/build-android.ps1. Never commit signing keys or passwords."
    )
}

android {
    namespace = "com.lyricposter.lyric_poster"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.lyricposter.lyric_poster"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signingPropertiesFile.isFile) {
            create("release") {
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
                storeFile = signingProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = signingProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: if (allowDebugSigning) signingConfigs.getByName("debug") else null
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
