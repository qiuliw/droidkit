import 'dart:io';

import 'package:droidkit/src/catalog/resolver.dart';
import 'package:droidkit/src/commands/droidkit_command.dart';
import 'package:droidkit/src/context.dart';
import 'package:droidkit/src/installer.dart';
import 'package:droidkit/src/java/jdk.dart';
import 'package:droidkit/src/sdk/android_sdk.dart';
import 'package:droidkit/src/util.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

/// Result level of a doctor check.
enum CheckStatus {
  /// All good.
  ok,

  /// Works, but something could be better.
  warning,

  /// Broken.
  error,

  /// Informational only.
  info,
}

/// One line of `droidkit doctor` output.
class DoctorCheck {
  /// Creates a [DoctorCheck].
  DoctorCheck(this.title, this.status, this.message, {this.hint, this.fix});

  /// What was checked.
  final String title;

  /// Outcome.
  final CheckStatus status;

  /// Details.
  final String message;

  /// How to resolve the problem manually.
  final String? hint;

  /// Automatic repair used by `doctor --fix`.
  final Future<void> Function()? fix;
}

/// `droidkit doctor`.
class DoctorCommand extends DroidkitCommand {
  /// Creates a [DoctorCommand].
  DoctorCommand(super.context) {
    argParser.addFlag(
      'fix',
      negatable: false,
      help: 'Repair what can be repaired automatically.',
    );
  }

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check the Android toolchain (SDK, JDK, emulator, Flutter) for problems.';

  @override
  Future<int> run() async {
    maxArgs(0);
    final ctx = await context();
    final fix = argResults!['fix'] as bool;
    var checks = await _runChecks(ctx);
    _print(checks);

    if (fix) {
      final fixable = checks.where(
        (c) =>
            c.fix != null &&
            (c.status == CheckStatus.error || c.status == CheckStatus.warning),
      );
      if (fixable.isEmpty) {
        logger.info('\nNothing to fix automatically.');
      } else {
        logger.info('');
        for (final check in fixable) {
          logger.info(styleBold.wrap('Fixing: ${check.title}'));
          try {
            await check.fix!();
          } on DroidkitException catch (e) {
            logger.err('  ${e.message}');
            if (e.hint != null) logger.info('  ${e.hint}');
          }
        }
        logger.info('\n${styleBold.wrap('Re-checking…')}');
        checks = await _runChecks(ctx);
        _print(checks);
      }
    }

    final errors = checks.where((c) => c.status == CheckStatus.error).length;
    final warnings = checks
        .where((c) => c.status == CheckStatus.warning)
        .length;
    logger.info('');
    if (errors == 0 && warnings == 0) {
      logger.success('No issues found!');
    } else {
      logger.info(
        '${errors > 0 ? red.wrap('$errors error(s)') : ''}'
        '${errors > 0 && warnings > 0 ? ', ' : ''}'
        '${warnings > 0 ? yellow.wrap('$warnings warning(s)') : ''}'
        '${fix || !checks.any((c) => c.fix != null && c.status != CheckStatus.ok) ? '' : '. Run `droidkit doctor --fix` to repair.'}',
      );
    }
    return errors > 0 ? ExitCode.software.code : ExitCode.success.code;
  }

  void _print(List<DoctorCheck> checks) {
    for (final c in checks) {
      final icon = switch (c.status) {
        CheckStatus.ok => green.wrap('✓')!,
        CheckStatus.warning => yellow.wrap('!')!,
        CheckStatus.error => red.wrap('✗')!,
        CheckStatus.info => cyan.wrap('•')!,
      };
      logger.info('$icon ${styleBold.wrap(c.title)}: ${c.message}');
      if (c.hint != null && c.status != CheckStatus.ok) {
        for (final line in c.hint!.split('\n')) {
          logger.info('    ${darkGray.wrap(line)}');
        }
      }
    }
  }

  Future<List<DoctorCheck>> _runChecks(DroidkitContext ctx) async {
    return ctx.spinner(
      'Inspecting your Android toolchain',
      () => _collect(ctx),
    );
  }

  Future<List<DoctorCheck>> _collect(DroidkitContext ctx) async {
    final installer = Installer(ctx);
    final host = ctx.host;
    final checks = <DoctorCheck>[];

    // Host ------------------------------------------------------------------
    checks.add(
      DoctorCheck(
        'Host',
        host.supportsEmulator && !host.isWsl
            ? CheckStatus.ok
            : CheckStatus.warning,
        host.description,
        hint: host.isWsl
            ? 'The emulator cannot use hardware acceleration or show a window '
                  'from WSL. Install droidkit on Windows for the emulator; '
                  'WSL can still build and deploy via adb over TCP.'
            : host.emulatorUnsupportedReason,
      ),
    );

    // JDK -------------------------------------------------------------------
    final jdk = await ctx.jdk();
    if (jdk != null) {
      checks.add(
        DoctorCheck(
          'Java',
          CheckStatus.ok,
          'JDK ${jdk.versionString} at ${jdk.home} (${jdk.source})',
        ),
      );
    } else {
      final all = await ctx.jdkLocator.findAll(configured: ctx.config.jdkHome);
      checks.add(
        DoctorCheck(
          'Java',
          CheckStatus.error,
          all.isEmpty
              ? 'no JDK found'
              : 'no usable JDK (${all.map((j) => 'Java ${j.majorVersion}: ${j.problem}').join('; ')})',
          hint:
              'Needs JDK $minJavaVersion–$maxJavaVersion. '
              'Fix: `droidkit jdk install`.',
          fix: () async => installer.installJdk(defaultJavaVersion),
        ),
      );
    }

    // SDK location ----------------------------------------------------------
    final location = await ctx.sdkLocation();
    final sdk = await ctx.sdk();
    final env = host.environment;
    if (!sdk.exists) {
      checks.add(
        DoctorCheck(
          'Android SDK',
          CheckStatus.error,
          'not found (would use ${sdk.root})',
          hint: 'Run `droidkit setup` for a guided install.',
          fix: () => installer.ensureCmdlineTools(sdk),
        ),
      );
    } else {
      checks.add(
        DoctorCheck(
          'Android SDK',
          isWritable(sdk.root) ? CheckStatus.ok : CheckStatus.warning,
          '${sdk.root} (${location.source})',
          hint:
              'The SDK directory is not writable; installing packages will '
              'fail. Fix its ownership or use --sdk-root.',
        ),
      );
    }
    final home = env['ANDROID_HOME'];
    final legacy = env['ANDROID_SDK_ROOT'];
    if (home != null &&
        legacy != null &&
        p.normalize(home) != p.normalize(legacy)) {
      checks.add(
        DoctorCheck(
          'Environment',
          CheckStatus.warning,
          'ANDROID_HOME ($home) and ANDROID_SDK_ROOT ($legacy) disagree',
          hint:
              'ANDROID_SDK_ROOT is deprecated; remove it from your shell '
              'profile.',
        ),
      );
    } else if (sdk.exists && (home == null || p.normalize(home) != sdk.root)) {
      checks.add(
        DoctorCheck(
          'Environment',
          CheckStatus.warning,
          home == null
              ? 'ANDROID_HOME is not set'
              : 'ANDROID_HOME points to $home, not ${sdk.root}',
          hint: 'Run `droidkit env --persist`, then open a new terminal.',
        ),
      );
    } else if (sdk.exists) {
      checks.add(
        DoctorCheck('Environment', CheckStatus.ok, 'ANDROID_HOME set'),
      );
    }

    if (!sdk.exists) return checks;

    // cmdline-tools ---------------------------------------------------------
    final misplaced = sdk.misplacedCmdlineTools;
    final cmdlineMajor = sdk.cmdlineToolsMajor;
    final flutterFound = await ctx.flutter.executable() != null;
    if (!sdk.hasCmdlineTools) {
      checks.add(
        DoctorCheck(
          'Command-line tools',
          CheckStatus.error,
          misplaced == null
              ? 'missing'
              : 'found at $misplaced, but Flutter expects '
                    'cmdline-tools/latest',
          hint: 'Fix: `droidkit doctor --fix`.',
          fix: () => installer.ensureCmdlineTools(sdk),
        ),
      );
    } else if (flutterFound && cmdlineMajor != null && cmdlineMajor >= 23) {
      checks.add(
        DoctorCheck(
          'Command-line tools',
          CheckStatus.warning,
          'version ${sdk.cmdlineToolsVersion}: Flutter reports "Android '
              'license status unknown" with 23+',
          hint:
              'See https://github.com/flutter/flutter/issues/191487. '
              '`droidkit doctor --fix` switches to $flutterCompatibleCmdlineTools '
              '(builds work either way).',
          fix: () => installer.ensureCmdlineTools(sdk, replace: true),
        ),
      );
    } else {
      checks.add(
        DoctorCheck(
          'Command-line tools',
          CheckStatus.ok,
          sdk.cmdlineToolsVersion == null
              ? _version(sdk, 'cmdline-tools;latest')
              : 'version ${sdk.cmdlineToolsVersion}',
        ),
      );
    }

    Future<void> Function() install(List<String> packages) => () async {
      final tools = await ctx.tools(sdk);
      await installer.acceptLicenses(tools);
      await installer.installPackages(tools, packages);
    };

    // platform-tools --------------------------------------------------------
    if (host.supportsPlatformTools) {
      checks.add(
        sdk.hasPlatformTools
            ? DoctorCheck(
                'Platform tools (adb)',
                CheckStatus.ok,
                _version(sdk, 'platform-tools'),
              )
            : DoctorCheck(
                'Platform tools (adb)',
                CheckStatus.error,
                'missing',
                fix: install(['platform-tools']),
              ),
      );
    } else {
      checks.add(
        DoctorCheck(
          'Platform tools (adb)',
          CheckStatus.warning,
          'Google ships no adb for ${host.description}',
          hint: 'Install adb from your distribution (e.g. `apt install adb`).',
        ),
      );
    }

    // platforms / build-tools ----------------------------------------------
    final installed = sdk.installedPackages();
    final compileSdk = await installer.flutterCompileSdk();
    final platforms = installed
        .where((i) => i.path.startsWith('platforms;'))
        .map((i) => i.path.substring('platforms;android-'.length))
        .toList();
    final hasTarget = platforms.any(
      (v) => v == '$compileSdk' || v == '$compileSdk.0',
    );
    checks.add(
      DoctorCheck(
        'Android platform',
        hasTarget ? CheckStatus.ok : CheckStatus.warning,
        platforms.isEmpty
            ? 'none installed'
            : 'installed: ${platforms.join(', ')}',
        hint:
            'Flutter builds against API $compileSdk by default. Gradle can '
            'download it on first build, but installing it now is faster.',
        fix: install(['platforms;android-$compileSdk']),
      ),
    );
    final buildTools = installed
        .where((i) => i.path.startsWith('build-tools;'))
        .map((i) => i.version)
        .toList();
    checks.add(
      DoctorCheck(
        'Build tools',
        buildTools.isEmpty ? CheckStatus.warning : CheckStatus.ok,
        buildTools.isEmpty ? 'none installed' : buildTools.join(', '),
        fix: buildTools.isEmpty
            ? () async {
                final latest = await _latestBuildTools(ctx);
                if (latest != null) await install([latest])();
              }
            : null,
      ),
    );

    // Licenses --------------------------------------------------------------
    final accepted = installer.licensesAccepted(sdk);
    checks.add(
      DoctorCheck(
        'Licenses',
        accepted ? CheckStatus.ok : CheckStatus.error,
        accepted ? 'accepted' : 'not accepted',
        hint: 'Fix: `droidkit licenses`.',
        fix: sdk.hasCmdlineTools && jdk != null
            ? () async => installer.acceptLicenses(await ctx.tools(sdk))
            : null,
      ),
    );

    // Emulator --------------------------------------------------------------
    if (host.supportsEmulator) {
      if (!sdk.hasEmulator) {
        checks.add(
          DoctorCheck(
            'Emulator',
            CheckStatus.warning,
            'not installed',
            hint:
                'Only needed to run apps without a physical device. '
                'Fix: `droidkit sdk install emulator`.',
            fix: install(['emulator']),
          ),
        );
      } else {
        checks.add(
          DoctorCheck('Emulator', CheckStatus.ok, _version(sdk, 'emulator')),
        );
        checks.add(await _accelerationCheck(ctx, sdk));
        final tools = await ctx.tools(sdk, needJava: false);
        final avds = await tools.listAvds();
        checks.add(
          DoctorCheck(
            'Virtual devices',
            avds.isEmpty ? CheckStatus.warning : CheckStatus.ok,
            avds.isEmpty ? 'none' : avds.join(', '),
            hint: 'Create one with `droidkit avd create`.',
          ),
        );
      }
    }

    // Flutter ---------------------------------------------------------------
    final flutter = await ctx.flutter.executable();
    if (flutter == null) {
      checks.add(
        DoctorCheck(
          'Flutter',
          CheckStatus.info,
          'not found on PATH (skipping Flutter integration checks)',
        ),
      );
    } else {
      final config = await ctx.flutter.config();
      final flutterSdk = config['android-sdk'];
      final flutterJdk = config['jdk-dir'];
      final sdkOk =
          flutterSdk == null ||
          p.normalize(flutterSdk) == p.normalize(sdk.root);
      final jdkOk =
          flutterJdk == null ||
          jdk == null ||
          p.normalize(flutterJdk) == p.normalize(jdk.home);
      // Only repair settings that point at something broken. Switching Flutter
      // between two working SDKs/JDKs is the user's call, even with --yes.
      final sdkBroken = !sdkOk && !ctx.sdkLocator.looksLikeSdk(flutterSdk);
      final jdkBroken =
          !jdkOk && await ctx.jdkLocator.inspect(flutterJdk, 'flutter') == null;
      checks.add(
        DoctorCheck(
          'Flutter',
          sdkOk && jdkOk
              ? CheckStatus.ok
              : sdkBroken || jdkBroken
              ? CheckStatus.error
              : CheckStatus.info,
          sdkOk && jdkOk
              ? 'uses this SDK${flutterJdk != null ? ' and JDK' : ''}'
              : [
                  if (!sdkOk)
                    'flutter config android-sdk is $flutterSdk'
                        '${sdkBroken ? ' (not a valid SDK)' : ''}',
                  if (!jdkOk)
                    'flutter config jdk-dir is $flutterJdk'
                        '${jdkBroken ? ' (not a usable JDK)' : ''}',
                ].join('; '),
          hint: sdkBroken || jdkBroken
              ? 'Fix: `droidkit doctor --fix` (runs `flutter config`).'
              : 'Flutter uses a different, working SDK/JDK. To switch, run '
                    '`flutter config${sdkOk ? '' : ' --android-sdk "${sdk.root}"'}'
                    '${jdkOk ? '' : ' --jdk-dir "${jdk.home}"'}`.',
          fix: sdkBroken || jdkBroken
              ? () async {
                  final ok = await ctx.flutter.configure(
                    sdkRoot: sdkBroken ? sdk.root : null,
                    jdkHome: jdkBroken ? jdk.home : null,
                  );
                  if (!ok) throw DroidkitException('`flutter config` failed.');
                }
              : null,
        ),
      );
    }

    // Disk ------------------------------------------------------------------
    final free = await freeBytes(sdk.root, host, ctx.runner);
    if (free != null) {
      checks.add(
        DoctorCheck(
          'Disk space',
          free < 8 * 1024 * 1024 * 1024 ? CheckStatus.warning : CheckStatus.ok,
          '${formatBytes(free)} free at ${sdk.root}',
          hint:
              'System images need ~2–4 GB each and emulators grow to '
              'several GB.',
        ),
      );
    }
    return checks;
  }

  static String _version(AndroidSdk sdk, String path) {
    final pkg = sdk
        .installedPackages()
        .where((i) => i.path == path)
        .firstOrNull;
    return pkg == null ? 'installed' : 'version ${pkg.version}';
  }

  Future<String?> _latestBuildTools(DroidkitContext ctx) async {
    final catalog = await ctx.catalogs.main();
    return Installer.resolver(catalog, ctx.host).latestBuildTools()?.path;
  }

  Future<DoctorCheck> _accelerationCheck(
    DroidkitContext ctx,
    AndroidSdk sdk,
  ) async {
    final host = ctx.host;
    if (host.isLinux) {
      final kvm = File('/dev/kvm');
      if (!kvm.existsSync()) {
        return DoctorCheck(
          'Acceleration',
          CheckStatus.error,
          '/dev/kvm not found — the emulator will be unusably slow',
          hint: host.isWsl
              ? 'WSL does not expose KVM to the emulator by default.'
              : 'Enable virtualization (VT-x/AMD-V) in your BIOS/UEFI and '
                    'load the kvm module (`sudo modprobe kvm_intel` or '
                    '`kvm_amd`).',
        );
      }
      try {
        kvm.openSync(mode: FileMode.append).closeSync();
      } on FileSystemException {
        return DoctorCheck(
          'Acceleration',
          CheckStatus.error,
          'no permission to use /dev/kvm',
          hint: 'Run `sudo usermod -aG kvm \$USER`, then log out and back in.',
        );
      }
    }
    final tools = await ctx.tools(sdk, needJava: false);
    final (ok, message) = await tools.accelCheck();
    return DoctorCheck(
      'Acceleration',
      ok ? CheckStatus.ok : CheckStatus.error,
      message.isEmpty ? (ok ? 'available' : 'unavailable') : message,
      hint: switch (host.os) {
        _ when ok => null,
        _ when host.isWindows =>
          'Enable "Windows Hypervisor Platform" in Windows Features, or '
              'install the Android Emulator hypervisor driver (AEHD).',
        _ when host.isMacOS =>
          'macOS uses Hypervisor.framework; make sure you are not inside a '
              'VM without nested virtualization.',
        _ => 'Check that virtualization is enabled in BIOS/UEFI.',
      },
    );
  }
}
