## 1.0.0

Initial release: install and manage the Android SDK, JDK and emulators for
Flutter without Android Studio.

- `setup`, `doctor [--fix]`, `start` / `stop` / `list`, `avd`, `images`, `sdk`,
  `jdk`, `licenses`, `env`, `clean`.
- Linux, macOS and Windows; verified downloads; CI-friendly.
- Installs command-line tools 22.0 by default (Flutter ≤ 3.47 reports
  "Android license status unknown" with 23.0, [flutter#191487](https://github.com/flutter/flutter/issues/191487)).
