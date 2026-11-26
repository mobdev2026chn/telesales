import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Play Store upload key: android/key.properties (gitignored) with storeFile, storePassword, keyAlias,
// keyPassword. Without it a release APK / bundle stops with an error (it is never signed with the
// debug key, which Google Play rejects). Debug builds do not need it.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasUploadKey = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) FileInputStream(keystorePropertiesFile).use { load(it) }
}
val localTestPropertiesFile = rootProject.file("local-test-key.properties")
val localTestProperties = Properties().apply {
    if (localTestPropertiesFile.exists()) FileInputStream(localTestPropertiesFile).use { load(it) }
}
val isLocalTestRelease = System.getenv("ASKEVA_LOCAL_TEST_RELEASE") == "1"
val localTestStoreFile = localTestProperties.getProperty("storeFile")?.let { file(it) }
val hasLocalTestKey = localTestPropertiesFile.exists() &&
    !localTestProperties.getProperty("storePassword").isNullOrBlank() &&
    !localTestProperties.getProperty("keyAlias").isNullOrBlank() &&
    !localTestProperties.getProperty("keyPassword").isNullOrBlank() &&
    localTestStoreFile?.isFile == true

android {
    namespace = "com.askeva.telesales_monitor"
    compileSdk = flutter.compileSdkVersion
    // Pinned to the locally installed NDK (flutter.ndkVersion wants 28.2.13676358, which isn't installed).
    ndkVersion = "30.0.16248370"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.askeva.telesales_monitor"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName + if (isLocalTestRelease) "-local-test" else ""
        if (isLocalTestRelease) {
            applicationIdSuffix = ".localtest"
            manifestPlaceholders["appLabel"] = "Telesales (Local Test)"
        } else {
            manifestPlaceholders["appLabel"] = "Telesales"
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
        if (localTestPropertiesFile.exists()) {
            create("localTest") {
                storeFile = localTestStoreFile
                storePassword = localTestProperties.getProperty("storePassword")
                keyAlias = localTestProperties.getProperty("keyAlias")
                keyPassword = localTestProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (isLocalTestRelease && hasLocalTestKey) {
                signingConfig = signingConfigs.getByName("localTest")
            } else if (hasUploadKey) {
                signingConfig = signingConfigs.getByName("release")
            }
            // R8 shrinking crashed the app on launch (the debug build, which isn't shrunk, runs fine).
            // Ship the same unshrunk code as debug; Dart code is still AOT-compiled.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

// A release APK or bundle must be signed with the matching key for its intended destination.
tasks.configureEach {
    if (name == "packageRelease" || name == "signReleaseBundle") {
        doFirst {
            if (isLocalTestRelease && !hasLocalTestKey) {
                throw GradleException(
                    "Local test signing is not configured. Run scripts/build_local_test_release.ps1."
                )
            }
            if (!isLocalTestRelease && !hasUploadKey) {
                throw GradleException(
                    "android/key.properties (Play upload key) is missing: release builds must be signed with the upload key."
                )
            }
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

dependencies {
    // Native upload queue for call recordings: retries with backoff even when the app is closed
    implementation("androidx.work:work-runtime-ktx:2.10.1")
}
