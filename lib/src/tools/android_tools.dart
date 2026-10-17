import 'dart:async';

import 'package:droidkit/src/process/process_runner.dart';
import 'package:droidkit/src/sdk/android_sdk.dart';

/// A running emulator as seen by adb.
class RunningEmulator {
  /// Creates a [RunningEmulator].
  const RunningEmulator(this.serial, this.avdName);

  /// adb serial, e.g. `emulator-5554`.
  final String serial;

  /// AVD name, or null if the emulator didn't answer.
  final String? avdName;
}

/// A device profile from `avdmanager list device`.
class DeviceProfile {
  /// Creates a [DeviceProfile].
  const DeviceProfile(this.id, this.name, this.oem, [this.tag]);

  /// Id passed to `avdmanager create avd --device`.
  final String id;

  /// Display name.
  final String name;

  /// Manufacturer.
  final String oem;

  /// Form factor tag (`android-tv`, `android-wear`…); null for phones and
  /// tablets.
  final String? tag;
}

/// Wraps sdkmanager, avdmanager, emulator and adb for one SDK.
class AndroidTools {
  /// Creates [AndroidTools].
  AndroidTools({
    required this.sdk,
    required this.runner,
    required this.environment,
  });

  /// The SDK the tools belong to.
  final AndroidSdk sdk;

  /// Process runner.
  final ProcessRunner runner;

  /// Environment (JAVA_HOME, ANDROID_HOME…) for every tool invocation.
  final Map<String, String> environment;

  List<String> get _sdkRootArg => ['--sdk_root=${sdk.root}'];

  // ---- sdkmanager -------------------------------------------------------

  /// Installs [packages] with sdkmanager, streaming output to the terminal.
  ///
  /// [onLine] receives each output line (for progress reporting); when null
  /// output goes straight to the terminal.
  Future<int> install(
    List<String> packages, {
    void Function(String line)? onLine,
  }) => runner.runInteractive(
    sdk.sdkmanager,
    [..._sdkRootArg, '--install', ...packages],
    environment: environment,
    // sdkmanager asks to accept licenses for new packages; the caller has
    // already obtained consent via `licenses`.
    autoAnswer: 'y',
    onLine: onLine,
  );

  /// Uninstalls [packages].
  Future<int> uninstall(List<String> packages) => runner.runInteractive(
    sdk.sdkmanager,
    [..._sdkRootArg, '--uninstall', ...packages],
    environment: environment,
  );

  /// Updates all installed packages.
  Future<int> update({void Function(String line)? onLine}) =>
      runner.runInteractive(
        sdk.sdkmanager,
        [..._sdkRootArg, '--update'],
        environment: environment,
        autoAnswer: 'y',
        onLine: onLine,
      );

  /// Runs `sdkmanager --licenses`. With [acceptAll] every license is
  /// accepted automatically; otherwise the user answers interactively.
  Future<int> licenses({
    required bool acceptAll,
    void Function(String line)? onLine,
  }) => runner.runInteractive(
    sdk.sdkmanager,
    [..._sdkRootArg, '--licenses'],
    environment: environment,
    autoAnswer: acceptAll ? 'y' : null,
    onLine: onLine,
  );

  // ---- avdmanager -------------------------------------------------------

  /// Names of all AVDs.
  Future<List<String>> listAvds() async {
    // `emulator -list-avds` is fast (native) — prefer it when installed.
    if (sdk.hasEmulator) {
      final r = await runner.run(sdk.emulator, [
        '-list-avds',
      ], environment: environment);
      if (r.ok) {
        return r.stdout
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && !l.startsWith('INFO'))
            .toList();
      }
    }
    if (!sdk.hasCmdlineTools) return [];
    final r = await runner.run(sdk.avdmanager, [
      'list',
      'avd',
      '-c',
    ], environment: environment);
    return r.stdout
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  /// Parses `avdmanager list device` output.
  static List<DeviceProfile> parseDevices(String output) {
    final devices = <DeviceProfile>[];
    String? id;
    String? name;
    String? oem;
    String? tag;
    void flush() {
      final currentId = id;
      if (currentId != null) {
        devices.add(
          DeviceProfile(currentId, name ?? currentId, oem ?? '', tag),
        );
      }
      id = name = oem = tag = null;
    }

    for (final line in output.split('\n')) {
      final idMatch = RegExp(r'^id:\s+\d+\s+or\s+"([^"]+)"').firstMatch(line);
      if (idMatch != null) {
        flush();
        id = idMatch.group(1);
        continue;
      }
      final nameMatch = RegExp(r'^\s+Name:\s+(.+)$').firstMatch(line);
      if (nameMatch != null) name = nameMatch.group(1)!.trim();
      final oemMatch = RegExp(r'^\s+OEM\s*:\s+(.+)$').firstMatch(line);
      if (oemMatch != null) oem = oemMatch.group(1)!.trim();
      final tagMatch = RegExp(r'^\s+Tag\s*:\s+(.+)$').firstMatch(line);
      if (tagMatch != null) tag = tagMatch.group(1)!.trim();
    }
    flush();
    return devices;
  }

  /// Device profiles (hardware definitions) avdmanager knows.
  Future<List<DeviceProfile>> listDevices() async {
    final r = await runner.run(sdk.avdmanager, [
      'list',
      'device',
    ], environment: environment);
    return r.ok ? parseDevices(r.stdout) : [];
  }

  /// Creates an AVD. Returns the avdmanager result.
  Future<RunResult> createAvd({
    required String name,
    required String systemImage,
    String? device,
    bool force = false,
  }) => runner.run(
    sdk.avdmanager,
    [
      'create',
      'avd',
      '--name',
      name,
      '--package',
      systemImage,
      if (device != null) ...['--device', device],
      if (force) '--force',
    ],
    environment: environment,
    // "Do you wish to create a custom hardware profile? [no]"
    stdinLines: const ['no'],
    timeout: const Duration(minutes: 2),
  );

  /// Deletes an AVD.
  Future<RunResult> deleteAvd(String name) => runner.run(sdk.avdmanager, [
    'delete',
    'avd',
    '--name',
    name,
  ], environment: environment);

  // ---- emulator ---------------------------------------------------------

  /// Checks hardware acceleration. Returns (usable, message).
  Future<(bool, String)> accelCheck() async {
    final r = await runner.run(
      sdk.emulator,
      ['-accel-check'],
      environment: environment,
      timeout: const Duration(seconds: 30),
    );
    // Output looks like: "accel:\n0\nKVM (version 12) is installed…\naccel".
    final text = '${r.stdout}\n${r.stderr}'
        .split('\n')
        .map((l) => l.trim())
        .where(
          (l) => l.isNotEmpty && !RegExp(r'^(accel:?|\d+|INFO.*)$').hasMatch(l),
        )
        .join(' ');
    return (r.exitCode == 0, text);
  }

  /// Starts an emulator detached from droidkit.
  Future<int> startEmulator(
    String avd,
    List<String> extraArgs, {
    String? logFile,
  }) => runner.startDetached(
    sdk.emulator,
    ['-avd', avd, ...extraArgs],
    environment: environment,
    logFile: logFile,
  );

  // ---- adb --------------------------------------------------------------

  /// Serials of running emulators, with their AVD names.
  Future<List<RunningEmulator>> runningEmulators() async {
    if (!sdk.hasPlatformTools) return [];
    final r = await runner.run(
      sdk.adb,
      ['devices'],
      environment: environment,
      timeout: const Duration(seconds: 20),
    );
    final serials = RegExp(
      r'^(emulator-\d+)\s+\w+',
      multiLine: true,
    ).allMatches(r.stdout).map((m) => m.group(1)!).toList();
    return Future.wait(
      serials.map((s) async => RunningEmulator(s, await avdNameOf(s))),
    );
  }

  /// Asks a running emulator for its AVD name.
  Future<String?> avdNameOf(String serial) async {
    final r = await runner.run(
      sdk.adb,
      ['-s', serial, 'emu', 'avd', 'name'],
      environment: environment,
      timeout: const Duration(seconds: 10),
    );
    if (!r.ok) return null;
    final first = r.stdout
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty && l != 'OK', orElse: () => '');
    return first.isEmpty ? null : first;
  }

  /// Shuts an emulator down.
  Future<RunResult> killEmulator(String serial) => runner.run(
    sdk.adb,
    ['-s', serial, 'emu', 'kill'],
    environment: environment,
    timeout: const Duration(seconds: 20),
  );

  /// Waits until the emulator running [avd] has fully booted.
  ///
  /// Returns the serial, or null on timeout.
  Future<String?> waitForBoot(
    String avd, {
    Duration timeout = const Duration(minutes: 5),
    Duration pollInterval = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final running = await runningEmulators();
      final match = running.where((e) => e.avdName == avd).firstOrNull;
      if (match != null) {
        final r = await runner.run(
          sdk.adb,
          ['-s', match.serial, 'shell', 'getprop', 'sys.boot_completed'],
          environment: environment,
          timeout: const Duration(seconds: 10),
        );
        if (r.stdout.trim() == '1') return match.serial;
      }
      await Future<void>.delayed(pollInterval);
    }
    return null;
  }
}
