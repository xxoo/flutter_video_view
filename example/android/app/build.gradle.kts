plugins {
	id("com.android.application")
	id("dev.flutter.flutter-gradle-plugin")
}

android {
	namespace = "dev.xx.video_view_example"
	compileSdk = flutter.compileSdkVersion
	ndkVersion = flutter.ndkVersion

	compileOptions {
		sourceCompatibility = JavaVersion.VERSION_17
		targetCompatibility = JavaVersion.VERSION_17
	}

	defaultConfig {
		applicationId = "dev.xx.video_view_example"
		// You can update the following values to match your application needs.
		// For more information, see: https://flutter.dev/to/review-gradle-config.
		minSdk = flutter.minSdkVersion
		targetSdk = flutter.targetSdkVersion
		versionCode = flutter.versionCode
		versionName = flutter.versionName
	}

	buildTypes {
		release {
			// Signing with the debug keys for now, so `flutter run --release` works.
			signingConfig = signingConfigs.getByName("debug")
		}
	}
}

flutter {
	source = "../.."
}
