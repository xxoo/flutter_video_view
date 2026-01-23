group = "dev.xx.video_view"
version = "1.2.10"

plugins {
	id("com.android.library")
}

android {
	namespace = "dev.xx.video_view"
	compileSdk = flutter.compileSdkVersion

	defaultConfig {
		minSdk = flutter.minSdkVersion
	}

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
	val media3Version = "[1.9,1.10)"
	implementation("androidx.media3:media3-ui:$media3Version")
	implementation("androidx.media3:media3-exoplayer:$media3Version")
	implementation("androidx.media3:media3-exoplayer-hls:$media3Version")
	implementation("androidx.media3:media3-exoplayer-dash:$media3Version")
	implementation("androidx.media3:media3-exoplayer-smoothstreaming:$media3Version")
}

repositories {
	google()
	mavenCentral()
}

if (extensions.findByName("kotlin") == null) {
	apply(plugin = "kotlin-android")
	extensions.getByName("android").withGroovyBuilder {
		"kotlinOptions" {
			setProperty("jvmTarget", JavaVersion.VERSION_17.toString())
		}
	}
}