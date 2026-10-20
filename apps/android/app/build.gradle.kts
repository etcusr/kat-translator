plugins { id("com.android.application"); id("org.jetbrains.kotlin.plugin.compose") }
android {
    namespace = "org.openoffline.translator.android"
    compileSdk = 36
    defaultConfig {
        applicationId = "org.openoffline.translator.android"
        minSdk = 31; targetSdk = 36
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        versionCode = 21; versionName = "0.4.6"
        ndk { abiFilters += "arm64-v8a" }
    }
    sourceSets["main"].assets.srcDir("../../../assets/catalogs")
    sourceSets["main"].assets.srcDir("../../../assets/bundled/OCR")
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("generated/shared-media-assets").get().asFile)
    sourceSets["androidTest"].assets.srcDir("../../../tests/fixtures/android")
    packaging { jniLibs { useLegacyPackaging = false } }
    buildFeatures { compose = true }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    buildTypes { release { isMinifyEnabled = false } }
}
val syncSharedMediaAssets by tasks.registering(Sync::class) {
    into(layout.buildDirectory.dir("generated/shared-media-assets"))
    from(rootProject.file("../../assets/bundled/espeak-ng-data")) { into("espeak-ng-data") }
    from(rootProject.file("../../assets/bundled/VoicePreviews")) { into("VoicePreviews") }
    from(rootProject.file("../../assets/bundled/ThirdPartyNotices.txt"))
    from(rootProject.file("../../.build/android-media/assets")) { include("wayu-runtime.zip", "wayu-runtime.sha256") }
    from(rootProject.file("../../Dependencies/build/speech/silero_vad.onnx"))
}
tasks.named("preBuild") { dependsOn(syncSharedMediaAssets) }
dependencies {
    // Models ship in the APK; first recognition works offline without Play Services downloads.
    implementation("com.google.mlkit:text-recognition:16.0.1")
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
    implementation("com.google.mlkit:text-recognition-devanagari:16.0.1")
    implementation("com.google.mlkit:text-recognition-japanese:16.0.1")
    implementation("com.google.mlkit:text-recognition-korean:16.0.1")
    implementation("androidx.core:core-ktx:1.17.0")
    implementation("org.apache.commons:commons-compress:1.28.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20250517")
    implementation(project(":inference"))
    implementation(platform("androidx.compose:compose-bom:2026.03.00"))
    implementation("androidx.activity:activity-compose:1.12.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui-tooling-preview")
    androidTestImplementation(platform("androidx.compose:compose-bom:2026.03.00"))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.7.0")
}
