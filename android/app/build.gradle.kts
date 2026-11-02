import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Opt-in for automated tests: Flutter removes its test APK afterwards, so keep
// the user's installed app and local practice records under a separate ID.
val isolatedTestPackage = (project.findProperty("dart-defines") as? String)
    .orEmpty().split(",").filter { it.isNotEmpty() }.any {
        String(Base64.getDecoder().decode(it)) == "ISOLATED_TEST_PACKAGE=true"
    }

// A fresh QA identity keeps both the main app and yesterday's preview data intact.
val danceFlowTestPackage = (project.findProperty("dart-defines") as? String)
    .orEmpty().split(",").filter { it.isNotEmpty() }.any {
        String(Base64.getDecoder().decode(it)) == "DANCE_FLOW_TEST_PACKAGE=true"
    }

// Optional single-architecture distribution; runtime behaviour and version stay the same.
val arm64OnlyPackage = (project.findProperty("dart-defines") as? String)
    .orEmpty().split(",").filter { it.isNotEmpty() }.any {
        String(Base64.getDecoder().decode(it)) == "ARM64_ONLY=true"
    }

android {
    namespace = "com.pianoforparkinson.piano_practice"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    buildFeatures { prefab = true }
    externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt"); version = "3.22.1" } }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = if (danceFlowTestPackage)
            "com.pianoforparkinson.piano_practice.dance_flow_test"
        else if (isolatedTestPackage)
            "com.pianoforparkinson.piano_practice.validation"
        else "com.pianoforparkinson.piano_practice"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        if (arm64OnlyPackage) {
            ndk { abiFilters.clear(); abiFilters.add("arm64-v8a") }
        }
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        externalNativeBuild { cmake { arguments += "-DANDROID_STL=c++_shared" } }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("com.google.oboe:oboe:1.11.0") }

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
