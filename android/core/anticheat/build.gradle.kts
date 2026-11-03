plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "org.trailbound.core.anticheat"
    compileSdk = 37
    defaultConfig { minSdk = 28 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation(libs.coroutines.android)
    testImplementation(libs.junit)
}
