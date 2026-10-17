plugins { id("com.android.library") }
android {
    namespace = "org.openoffline.translator.inference"
    compileSdk = 36
    ndkVersion = "28.2.13676358"
    defaultConfig {
        minSdk = 31
        ndk { abiFilters += "arm64-v8a" }
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        externalNativeBuild { cmake {
            arguments += listOf("-DANDROID_STL=c++_shared", "-DCMAKE_BUILD_TYPE=RelWithDebInfo")
            targets += listOf("kat_index", "kat_media", "kat_opus")
        } }
    }
    externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt"); version = "3.22.1" } }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
}
androidComponents {
    onVariants { variant ->
        // Loaded only after a baseline HWCAP check; never a DT_NEEDED dependency.
        variant.sources.jniLibs?.addStaticSourceDirectory("../../../.build/android-media/whisper-optimized")
    }
}
dependencies {
    implementation("com.ibm.icu:icu4j:78.3")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}
