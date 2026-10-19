# Firestore pagination example

## Android setup

Use Flutter 3.47 or later and JDK 17 or later. The Android example uses AGP
9.1.0, Gradle 9.3.1, and AGP's built-in Kotlin support with Kotlin 2.4.0. The separate
`kotlin-android` plugin is no longer applied. `android.newDsl=false` remains
required by Flutter's Gradle plugin; it does not disable built-in Kotlin.
The Kotlin declaration in `settings.gradle` uses `apply false` to upgrade AGP's
bundled compiler to Flutter's supported version without applying the legacy plugin.

Flutter 3.47.7 may warn that `firebase_core` applies the legacy Kotlin plugin.
With `firebase_core` 5.0.0 this is a build-script scanner false positive: the
legacy plugin is inside a compatibility condition that is inactive when built-in
Kotlin is enabled on AGP 9. The Gradle runtime plugin state was checked during
the migration.

The example follows Flutter's Android SDK defaults (currently minimum API 24,
compile/target API 36). These build requirements apply to this example app;
the pagination package itself contains no native Android module.

1. Register an Android app in your Firebase project with application ID
   `space.cogitare.paginate_firestore_example`.
2. Download its `google-services.json` into `android/app/`. This file is ignored
   by Git and must be supplied locally.
3. Run these commands from the `example` directory:

```sh
flutter pub get
flutter build apk --debug
flutter run
```

The example queries a `users` collection ordered by `name`. Configure Firestore
and its rules in your Firebase project before running it.

See Flutter's [built-in Kotlin migration guide](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers).
