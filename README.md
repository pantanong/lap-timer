# Lap Timer

GPS lap timer for cars, karts, motorcycles and bicycles, with sectors,
pit lane mode and a brake point coach. Flutter app for Android and iOS.

- Product spec: [`docs/SPEC.md`](docs/SPEC.md)
- UI mockups: [`docs/mockups/`](docs/mockups)

## Install the latest build (Android)

1. Open the repository's **Actions** tab on GitHub and pick the newest green
   **CI** run.
2. Download the `lap-timer-apk-…` artifact (a zip) and unzip it.
3. Open `app-release.apk` on the phone and allow installing from this source.

## Code layout

```
lib/
  main.dart            composition root: builds infrastructure, injects it
  app/                 MaterialApp, router
  core/                shared building blocks (Result, geometry)
  theme/               colours and theme (no raw colours in widgets)
  l10n/                English strings (ARB); add languages here later
  features/<feature>/
    domain/            pure Dart: models and calculations, fully unit-tested
    data/              repositories and sources (GPS, files, database)
    presentation/      screens (dumb widgets) + one Notifier per screen
```

Rules: dependencies only point downward (presentation → data → domain);
every side effect (GPS, files, clock) sits behind an injectable interface;
every public class and function has a `///` comment explaining what and why.

## Develop

```bash
flutter pub get
flutter gen-l10n
dart format lib test
flutter analyze --fatal-infos
flutter test
```

Testing without a car: choose **Simulator** (virtual car on a virtual track)
or **Replay** (a recorded GPS log) as the GPS source on the home screen.
