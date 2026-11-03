import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
}

android {
    namespace = "org.trailbound.app"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.premisei3.veilwalker"   // permanent on Play; code namespace stays org.trailbound.app
        minSdk = 28          // Android 9
        targetSdk = 36       // Play requirement for new apps (Aug 2026)
        versionCode = 3
        versionName = "0.3.0"
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64") }
    }

    // Upload key lives outside the repo (C:/Users/Support/.veilwalker). Without it, release builds are unsigned.
    val keyProps = Properties().apply {
        val f = file(System.getProperty("user.home") + "/.veilwalker/keystore.properties")
        if (f.exists()) f.inputStream().use { load(it) }
    }
    signingConfigs {
        if (keyProps.isNotEmpty()) create("upload") {
            storeFile = file(keyProps.getProperty("storeFile"))
            storePassword = keyProps.getProperty("storePassword")
            keyAlias = keyProps.getProperty("keyAlias")
            keyPassword = keyProps.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfigs.findByName("upload")?.let { signingConfig = it }
        }
        // Release code (R8) with the debug key: installs over a debug build without wiping data, for testing.
        create("staging") {
            initWith(getByName("release"))
            signingConfig = signingConfigs.getByName("debug")
            matchingFallbacks += "release"
        }
    }
    // Per-ABI splits through the AAB so Arti + Snowflake native libs stay small per install.
    bundle { abi { enableSplit = true } }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true }
}

dependencies {
    implementation(project(":core:data"))
    implementation(project(":core:steps"))
    implementation(project(":core:ledger"))
    implementation(project(":core:net"))
    implementation(project(":core:identity"))
    implementation(project(":core:route"))
    implementation(project(":core:achievements"))
    implementation(project(":core:snowflake"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime)
    implementation(libs.androidx.lifecycle.viewmodel)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.material3)
    implementation(libs.compose.tooling.preview)
    debugImplementation(libs.compose.tooling)

    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
    implementation(libs.hilt.work)
    implementation(libs.hilt.navigation.compose)
    implementation(libs.work.runtime)
}
