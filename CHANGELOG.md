## 0.1.0

Initial release.

- `droidkit setup`: one-command Android toolchain for Flutter (JDK, command-line
  tools, licenses, platform, build-tools, emulator, virtual device,
  `flutter config`, shell environment). Reuses an existing SDK/JDK when found.
- `droidkit doctor [--fix]`: diagnoses SDK layout, JDK range, licenses,
  hardware acceleration, WSL, Flutter configuration and disk space, and repairs
  what it can.
- `droidkit start` / `stop` / `list` and `droidkit avd create|delete|devices`
  for emulators, including `--headless --wait` for CI.
- `droidkit sdk list|install|uninstall|update` and `droidkit images`, backed by
  Google's repository catalog (fast, no JVM needed for listing).
- `droidkit jdk install|list`: Eclipse Temurin downloads, verified by SHA-256.
- `droidkit env [--persist]` for bash, zsh, fish, PowerShell and cmd.
- `droidkit licenses`, `droidkit clean`.
- Installs command-line tools 22.0 by default because Flutter <= 3.47 reports
  "Android license status unknown" with 23.0
  ([flutter#191487](https://github.com/flutter/flutter/issues/191487)).
