plugins { id("com.android.library") version "9.1.0" }
android {
 namespace = "io.flutter.plugins.videoplayer.cachetests"
 compileSdk = 36
 defaultConfig { minSdk = 24 }
 sourceSets {
  getByName("main") { java.srcDir(layout.buildDirectory.dir("nativeMain").get().asFile) }
  getByName("test") { java.srcDir(layout.buildDirectory.dir("nativeTest").get().asFile) }
 }
 compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
 testOptions { unitTests { isIncludeAndroidResources = true; all { it.jvmArgs("-Xmx2G"); it.testLogging { events("passed", "failed", "skipped"); showStandardStreams = true } } } }
}
dependencies {
 implementation("androidx.media3:media3-exoplayer:1.9.2")
 testImplementation("junit:junit:4.13.2")
 testImplementation("org.mockito:mockito-core:5.23.0")
 testImplementation("androidx.test:core:1.7.0")
 testImplementation("org.robolectric:robolectric:4.16")
}
val cacheSources by tasks.registering(Copy::class) {
 from("../android/src/main/java") { include("**/DanceMediaCache.java", "**/DanceCacheEvictor.java") }
 into(layout.buildDirectory.dir("nativeMain"))
}
val cacheTestSources by tasks.registering(Copy::class) {
 from("../android/src/test/java") { include("**/DanceMediaCacheTest.java") }
 into(layout.buildDirectory.dir("nativeTest"))
}
tasks.matching { it.name.startsWith("compile") }.configureEach { dependsOn(cacheSources, cacheTestSources) }
