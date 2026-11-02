plugins {
    id("com.android.application")
}

android {
    namespace = "com.locamarket.smsforwarder"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.locamarket.smsforwarder"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation("androidx.work:work-runtime-ktx:2.10.5")
    testImplementation("junit:junit:4.13.2")
}
