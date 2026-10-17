import 'dart:io';

import 'package:droidkit/src/process/process_runner.dart';

/// Host operating system.
enum HostOs {
  /// Linux (including WSL).
  linux('linux', 'linux'),

  /// macOS.
  macos('macosx', 'mac'),

  /// Windows.
  windows('windows', 'windows');

  const HostOs(this.catalogName, this.adoptiumName);

  /// The name used by Google's SDK repository (`<host-os>`).
  final String catalogName;

  /// The name used by the Adoptium API.
  final String adoptiumName;
}

/// Host CPU architecture.
enum HostArch {
  /// x86_64 / AMD64.
  x64('x64', 'x64', 'x86_64'),

  /// ARM64 / aarch64.
  arm64('aarch64', 'aarch64', 'arm64-v8a'),

  /// Anything else (32-bit x86, 32-bit ARM, RISC-V…).
  other('other', 'other', 'unsupported');

  const HostArch(this.catalogName, this.adoptiumName, this.systemImageAbi);

  /// The name used by Google's SDK repository (`<host-arch>`).
  final String catalogName;

  /// The name used by the Adoptium API.
  final String adoptiumName;

  /// The emulator system image ABI that runs natively on this CPU.
  final String systemImageAbi;
}

/// Everything droidkit needs to know about the machine it runs on.
class HostPlatform {
  /// Creates a [HostPlatform].
  const HostPlatform({
    required this.os,
    required this.arch,
    required this.environment,
    this.isWsl = false,
  });

  /// Detects the current host.
  static Future<HostPlatform> detect({
    ProcessRunner runner = const ProcessRunner(),
    Map<String, String>? environment,
  }) async {
    final env = environment ?? Platform.environment;
    final os = Platform.isWindows
        ? HostOs.windows
        : Platform.isMacOS
        ? HostOs.macos
        : HostOs.linux;
    final arch = await _detectArch(os, runner, env);
    var wsl = false;
    if (os == HostOs.linux) {
      wsl =
          env.containsKey('WSL_DISTRO_NAME') || env.containsKey('WSL_INTEROP');
      if (!wsl) {
        try {
          final version = File('/proc/version').readAsStringSync();
          wsl = version.toLowerCase().contains('microsoft');
        } on FileSystemException {
          // Not available.
        }
      }
    }
    return HostPlatform(os: os, arch: arch, environment: env, isWsl: wsl);
  }

  static Future<HostArch> _detectArch(
    HostOs os,
    ProcessRunner runner,
    Map<String, String> env,
  ) async {
    String raw;
    switch (os) {
      case HostOs.windows:
        // PROCESSOR_ARCHITEW6432 is set when a 32-bit process runs on 64-bit.
        raw =
            env['PROCESSOR_ARCHITEW6432'] ??
            env['PROCESSOR_ARCHITECTURE'] ??
            '';
      case HostOs.macos:
        // `uname -m` lies under Rosetta; ask the kernel directly.
        final r = await runner.run('sysctl', ['-n', 'hw.optional.arm64']);
        if (r.ok && r.stdout.trim() == '1') return HostArch.arm64;
        raw = (await runner.run('uname', ['-m'])).stdout;
      case HostOs.linux:
        raw = (await runner.run('uname', ['-m'])).stdout;
    }
    return parseArch(raw);
  }

  /// Maps a raw architecture string (uname/Windows env) to a [HostArch].
  static HostArch parseArch(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'x86_64':
      case 'amd64':
      case 'x64':
        return HostArch.x64;
      case 'arm64':
      case 'aarch64':
      case 'armv8l':
        return HostArch.arm64;
      default:
        return HostArch.other;
    }
  }

  /// Host operating system.
  final HostOs os;

  /// Host CPU architecture.
  final HostArch arch;

  /// Environment variables.
  final Map<String, String> environment;

  /// Whether this is Linux running inside Windows Subsystem for Linux.
  final bool isWsl;

  /// Whether this is Windows.
  bool get isWindows => os == HostOs.windows;

  /// Whether this is macOS.
  bool get isMacOS => os == HostOs.macos;

  /// Whether this is Linux.
  bool get isLinux => os == HostOs.linux;

  /// Whether we're running in CI.
  bool get isCi =>
      environment['CI']?.toLowerCase() == 'true' ||
      environment.containsKey('GITHUB_ACTIONS') ||
      environment.containsKey('GITLAB_CI') ||
      environment.containsKey('BUILDKITE');

  /// The user's home directory.
  String get homeDirectory =>
      (isWindows ? environment['USERPROFILE'] : environment['HOME']) ?? '.';

  /// Whether Google ships an Android emulator for this host.
  ///
  /// As of 2026 the emulator exists for linux-x64, macOS (x64 + arm64) and
  /// windows-x64 only.
  bool get supportsEmulator => switch ((os, arch)) {
    (HostOs.macos, HostArch.x64 || HostArch.arm64) => true,
    (HostOs.linux || HostOs.windows, HostArch.x64) => true,
    _ => false,
  };

  /// Whether Google ships native platform-tools (adb) for this host.
  bool get supportsPlatformTools => switch ((os, arch)) {
    (HostOs.linux, HostArch.arm64 || HostArch.other) => false,
    (_, HostArch.other) => false,
    _ => true,
  };

  /// Executable suffix for scripts in `cmdline-tools/latest/bin`.
  String get scriptSuffix => isWindows ? '.bat' : '';

  /// Executable suffix for native binaries (emulator, adb).
  String get exeSuffix => isWindows ? '.exe' : '';

  /// The conventional Android SDK location for this OS (what Android Studio
  /// would use).
  String get defaultSdkRoot => switch (os) {
    HostOs.macos => '$homeDirectory/Library/Android/sdk',
    HostOs.windows =>
      '${environment['LOCALAPPDATA'] ?? '$homeDirectory\\AppData\\Local'}'
          '\\Android\\Sdk',
    HostOs.linux => '$homeDirectory/Android/Sdk',
  };

  /// A human description such as `linux-x64 (WSL)`.
  String get description =>
      '${os.name}-${arch == HostArch.arm64 ? 'arm64' : arch.name}'
      '${isWsl ? ' (WSL)' : ''}';

  /// Explains why the emulator is not available, or null if it is.
  String? get emulatorUnsupportedReason {
    if (supportsEmulator) return null;
    if (arch == HostArch.other) {
      return 'The Android emulator only runs on 64-bit x86 or ARM hosts.';
    }
    return 'Google does not publish the Android emulator for $description. '
        'Build for Android here and run on a physical device instead '
        '(connect it over USB, or use `adb pair` for wireless debugging).';
  }
}
