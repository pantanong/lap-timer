# Vendored: flutter_blue_plus 1.34.5

Copied from pub.dev (BSD-3-Clause, see `LICENSE`) so the app keeps the
permissively licensed 1.x line (2.x needs a paid licence for commercial use).

Only change: `android/build.gradle` `compileSdkVersion 33` → `35`, because
its AndroidX dependencies require compiling against API 34 or later.
Used only by `lib/features/gps/data/dragy_gps_source.dart`.
