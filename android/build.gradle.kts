group = "dev.xx.video_view"
version = "1.2.9"

plugins {
	id("com.android.library")
}

android {
	namespace = "dev.xx.video_view"
	compileSdk = flutter.compileSdkVersion

	compileOptions {
		sourceCompatibility = JavaVersion.VERSION_17
		targetCompatibility = JavaVersion.VERSION_17
	}

	sourceSets {
		getByName("main") {
			java.directories.add("src/main/kotlin")
		}
	}
}

dependencies {
	implementation("androidx.media3:media3-ui:[1.9,1.10)")
	implementation("androidx.media3:media3-exoplayer:[1.9,1.10)")
	implementation("androidx.media3:media3-exoplayer-hls:[1.9,1.10)")
	implementation("androidx.media3:media3-exoplayer-dash:[1.9,1.10)")
	implementation("androidx.media3:media3-exoplayer-smoothstreaming:[1.9,1.10)")
}

repositories {
	google()
	mavenCentral()
}

if (GradleVersion.current() < GradleVersion.version("9.0")) {
	apply(plugin = "kotlin-android")
	extensions.getByName("android").withGroovyBuilder {
		"kotlinOptions" {
			setProperty("jvmTarget", JavaVersion.VERSION_17.toString())
		}
	}
}