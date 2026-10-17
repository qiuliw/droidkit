# droidkit

[![pub package](https://img.shields.io/pub/v/droidkit.svg)](https://pub.dev/packages/droidkit)
[![CI](https://github.com/sawongam/droidkit/actions/workflows/ci.yml/badge.svg)](https://github.com/sawongam/droidkit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**The Android toolchain for Flutter — without installing Android Studio.**

droidkit installs and manages everything Flutter needs to build and run Android
apps: a JDK, the Android SDK command-line tools, platforms, build tools, the
emulator and virtual devices. It wires them into Flutter and your shell, and
diagnoses (and fixes) broken setups.

```sh
dart pub global activate droidkit
droidkit setup
```

That's it: a few minutes later `flutter doctor` shows a green Android
toolchain and `droidkit start` boots an emulator.

## Why

Android Studio is a multi-gigabyte IDE. Many Flutter developers use VS Code,
Zed, Neovim or a headless machine and only need the SDK and an emulator.
Setting those up by hand means finding the right command-line tools zip,
getting the `cmdline-tools/latest` folder layout right, finding a compatible
JDK, accepting licenses, choosing a system image for your CPU, creating an AVD,
and exporting environment variables — on every machine and CI runner.

droidkit does all of that, on **Linux, macOS and Windows**, and it's written
in Dart, so every Flutter developer already has what it needs to run it.

## Features

- **One-command setup** — `droidkit setup` walks you through it, or
  `droidkit --yes setup` does it unattended.
- **Reuses what you have** — finds existing SDKs (`ANDROID_HOME`,
  `flutter config`, Android Studio's default folder) and JDKs (`JAVA_HOME`,
  `PATH`, Android Studio's bundled JBR) and only installs what's missing.
- **Always current, never hardcoded** — reads Google's SDK repository catalog
  to pick the newest stable packages, and the API level your installed Flutter
  actually builds against.
- **Verified downloads** — every archive is checked against Google's SHA-1 or
  Adoptium's SHA-256, downloaded to a temp file, and moved into place
  atomically. Interrupted runs never leave a half-installed SDK.
- **`droidkit doctor --fix`** — checks the SDK layout, JDK version, licenses,
  hardware acceleration (KVM / Hypervisor / WHPX), WSL, `flutter config`,
  environment variables and disk space, and repairs what it can.
- **Emulator management** — create, list, start (`--headless --wait` for CI),
  stop and delete emulators; lists system images that actually run on your CPU.
- **JDK management** — downloads Eclipse Temurin into `~/.droidkit/jdk`
  without touching your system Java.
- **Shell integration** — `eval "$(droidkit env)"` or `droidkit env --persist`
  for bash, zsh, fish, PowerShell and cmd.
- **CI-friendly** — non-interactive when there's no terminal, meaningful exit
  codes, plain log output, `--yes` for license acceptance.

## Installation

Requires the Dart SDK (bundled with Flutter).

```sh
dart pub global activate droidkit
```

Make sure the pub cache `bin` directory is on your `PATH` (`~/.pub-cache/bin`
on macOS/Linux, `%LOCALAPPDATA%\Pub\Cache\bin` on Windows). Dart prints a
warning with instructions if it isn't.

## Quick start

```sh
droidkit setup      # JDK → SDK → licenses → platform/build-tools → emulator
droidkit start      # boot the emulator in the background
flutter run
```

Already have an SDK? Check it instead:

```sh
droidkit doctor
droidkit doctor --fix
```

## Commands

| Command | What it does |
| --- | --- |
| `droidkit setup` | Install and configure the full toolchain. |
| `droidkit doctor [--fix]` | Diagnose (and repair) the toolchain. |
| `droidkit start [name] [-- emulator flags]` | Start an emulator in the background. `--headless`, `--wait`, `--cold`, `--wipe`, `--gpu`. |
| `droidkit stop [name \| --all]` | Stop running emulators. |
| `droidkit list` | List emulators and whether they're running. |
| `droidkit avd create \| delete \| devices` | Manage emulators and hardware profiles. |
| `droidkit images [--api N] [--tag T]` | System images that run on this computer. |
| `droidkit sdk list [-a] \| install \| uninstall \| update` | Manage SDK packages. |
| `droidkit jdk install [--version N] \| list` | Manage JDKs. |
| `droidkit licenses [--show]` | Review and accept the Android SDK licenses. |
| `droidkit env [--shell S] [--persist \| --unpersist]` | Shell environment for the toolchain. |
| `droidkit clean [--all]` | Remove caches; `--all` also removes what droidkit installed. |

Global options: `--sdk-root <path>` (use or create an SDK elsewhere),
`--yes` / `-y`, `--verbose` / `-v`. Run `droidkit help <command>` for details.

### `setup` options

| Option | Default | |
| --- | --- | --- |
| `--api` | your Flutter's `compileSdk` | Android platform (and emulator) API level |
| `--image` | `google_apis_playstore` | `google_apis`, `default`, `google_atd`, `aosp_atd` |
| `--device` | newest Pixel profile | see `droidkit avd devices` |
| `--avd-name` | e.g. `Pixel_9_API_36` | |
| `--[no-]emulator` | on | `--no-emulator` for CI or physical-device setups |
| `--ndk` | off | also install the NDK version Flutter expects |
| `--jdk` | `auto` | `auto` (download if needed), `system`, or a JDK path |
| `--cmdline-tools` | `22.0` | or `latest` (see [Known issues](#known-issues)) |
| `--[no-]persist-env` | ask | add `ANDROID_HOME` & `PATH` to your shell profile |
| `--[no-]flutter-config` | on | run `flutter config --android-sdk/--jdk-dir` |

## Using droidkit in CI

```yaml
# GitHub Actions
- uses: subosito/flutter-action@v2
- run: dart pub global activate droidkit
- run: droidkit --yes setup --no-emulator   # also runs `flutter config`
- run: flutter build apk
```

Need `ANDROID_HOME`/`adb` in later shell steps too? Run
`eval "$(droidkit env)"` at the start of that step.

Integration tests on an emulator (Linux runners with KVM enabled):

```sh
droidkit --yes avd create --image google_atd --name ci
droidkit start ci --headless --wait --timeout 600
flutter test integration_test
droidkit stop --all
```

`--yes` is required to accept the Android SDK licenses non-interactively; read
them first with `droidkit licenses --show`.

## Platform support

| Host | SDK & builds | Emulator |
| --- | --- | --- |
| Linux x64 | ✅ | ✅ (needs KVM) |
| macOS Apple Silicon | ✅ | ✅ (arm64 images) |
| macOS Intel | ✅ | ✅ |
| Windows x64 | ✅ | ✅ (needs WHPX or AEHD) |
| Linux arm64 | ⚠️ builds work; install `adb` from your distro | ❌ not published by Google |
| Windows arm64 | ✅ | ❌ not published by Google |
| WSL 2 | ✅ | ❌ use the Windows side for the emulator |

On unsupported hosts droidkit sets up the SDK and explains how to use a
physical device (USB, or `adb pair` for wireless debugging).

## Where things go

| What | Location |
| --- | --- |
| Android SDK | Existing SDK if found, else `~/Android/Sdk` (Linux), `~/Library/Android/sdk` (macOS), `%LOCALAPPDATA%\Android\Sdk` (Windows), or `--sdk-root` |
| JDKs installed by droidkit | `~/.droidkit/jdk` |
| Settings, catalog cache, emulator logs | `~/.droidkit` (override with `DROIDKIT_HOME`) |
| Emulators | `~/.android/avd` (or `ANDROID_AVD_HOME`) |

droidkit never modifies your shell profile, Flutter config or system Java
without asking (or an explicit flag).

## Environment variables

| Variable | Effect |
| --- | --- |
| `DROIDKIT_HOME` | Where droidkit keeps its own files (default `~/.droidkit`). |
| `HTTPS_PROXY` / `HTTP_PROXY` / `NO_PROXY` | Used for all downloads. |
| `DROIDKIT_REPOSITORY_URL` | Alternative Google repository mirror. |
| `DROIDKIT_NO_UPDATE_CHECK` | Disable the once-a-day new-version check. |
| `ANDROID_HOME`, `ANDROID_AVD_HOME`, `JAVA_HOME` | Respected as usual. |

## Troubleshooting

**`flutter doctor` says "Android license status unknown".** You have Android
command-line tools 23+, which Flutter 3.47 and earlier can't read license
status from. Builds still work. `droidkit doctor --fix` switches to 22.0.

**The emulator is extremely slow / won't start on Linux.** Run
`droidkit doctor`. You most likely need virtualization enabled in BIOS/UEFI
and your user in the `kvm` group: `sudo usermod -aG kvm $USER`, then log out
and back in. Logs from `droidkit start` are in `~/.droidkit/logs/`.

**Windows: "hypervisor" errors.** Enable *Windows Hypervisor Platform* in
*Turn Windows features on or off*, or install the Android Emulator hypervisor
driver (AEHD).

**Behind a corporate proxy.** Set `HTTPS_PROXY`. droidkit uses it for its own
downloads; `sdkmanager` may additionally need `--proxy` settings in
`~/.android/androidtool.cfg`.

**Not enough disk space.** System images need about 2 GB each and emulators
grow to several GB. Put the SDK elsewhere with `--sdk-root` and droidkit's own
files with `DROIDKIT_HOME`.

## Known issues

- Android command-line tools 23.0 deprecated `sdkmanager --licenses` in favour
  of the new `android` CLI, which makes Flutter ≤ 3.47 report *Android license
  status unknown* ([flutter#191487](https://github.com/flutter/flutter/issues/191487)).
  droidkit therefore installs command-line tools **22.0** by default; pass
  `--cmdline-tools latest` to opt in to 23. `droidkit sdk update` warns if it
  upgrades them.

## Uninstall

```sh
droidkit clean --all                  # removes what droidkit installed (asks first)
dart pub global deactivate droidkit
```

## Contributing

Issues and pull requests are welcome. Run the checks before sending a PR:

```sh
dart format .
dart analyze --fatal-infos
dart test
```

## License

MIT — see [LICENSE](LICENSE). droidkit is not affiliated with Google. Android
SDK components are downloaded from Google and governed by their own licenses,
which you accept via `droidkit licenses`.
