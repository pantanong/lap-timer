# Lap Timer

GPS lap timer for cars, karts, motorcycles and bicycles, with sectors,
pit lane mode and a brake point coach. Flutter app for Android and iOS.

- Product spec: [`docs/SPEC.md`](docs/SPEC.md)
- UI mockups: [`docs/mockups/`](docs/mockups)

## Install on Android

Open on the phone and install:
**https://github.com/pantanong/lap-timer/releases/latest/download/lap-timer.apk**

- That link is always the newest build of `main`.
- Builds of other branches (to try a change before merging) are listed as
  *Pre-release* on https://github.com/pantanong/lap-timer/releases
- New builds install over the old one; tracks and sessions are kept.

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
