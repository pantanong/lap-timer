# App signing

`sideload-release.jks` signs every build made by CI so that a new APK can be
installed over the previous one (Android refuses an update signed with a
different key, and uninstalling first would delete tracks and sessions).

This key and its password are public (the repository is public). That is
acceptable for builds the owner installs by hand, but **not** for a Play
Store release: before publishing, create a private upload key, keep it out
of the repository (GitHub secret), and enrol in Play App Signing.
