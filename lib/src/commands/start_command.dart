import 'dart:io';

import 'package:droidkit/src/commands/droidkit_command.dart';
import 'package:droidkit/src/context.dart';
import 'package:droidkit/src/tools/android_tools.dart';
import 'package:droidkit/src/ui/task.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

/// `droidkit start`.
class StartCommand extends DroidkitCommand {
  /// Creates a [StartCommand].
  StartCommand(super.context) {
    argParser
      ..addFlag(
        'cold',
        negatable: false,
        help: 'Cold boot (ignore the saved snapshot).',
      )
      ..addFlag(
        'wipe',
        negatable: false,
        help: 'Factory-reset the emulator before booting.',
      )
      ..addFlag(
        'headless',
        negatable: false,
        help: 'No window, audio or boot animation (CI).',
      )
      ..addOption(
        'gpu',
        help: 'GPU mode passed to the emulator.',
        allowed: [
          'auto',
          'host',
          'swiftshader_indirect',
          'angle_indirect',
          'guest',
        ],
      )
      ..addFlag(
        'wait',
        abbr: 'w',
        negatable: false,
        help: 'Wait until Android has fully booted.',
      )
      ..addOption(
        'timeout',
        help: 'Seconds to wait with --wait.',
        defaultsTo: '300',
      )
      ..addFlag(
        'set-default',
        negatable: false,
        help: 'Remember this emulator as the default.',
      );
  }

  @override
  String get name => 'start';

  @override
  String get description =>
      'Start an emulator in the background. Extra emulator flags can follow '
      '`--`.';

  @override
  String get invocation => 'droidkit start [<name>] [-- <emulator flags>]';

  @override
  Future<int> run() async {
    final ctx = await context();
    final sdk = await ctx.sdk();
    if (!sdk.hasEmulator) {
      throw DroidkitException(
        'The emulator is not installed.',
        hint: ctx.host.supportsEmulator
            ? 'Run `droidkit setup` or `droidkit avd create`.'
            : ctx.host.emulatorUnsupportedReason,
        exitCode: ExitCode.unavailable,
      );
    }
    final tools = await ctx.tools(sdk, needJava: false);
    final avds = await tools.listAvds();
    if (avds.isEmpty) {
      throw DroidkitException(
        'You have no emulators yet.',
        hint: 'Create one with `droidkit avd create`.',
        exitCode: ExitCode.unavailable,
      );
    }

    final name = _pickAvd(ctx, avds);
    final extra = rest.isNotEmpty && rest.first == name ? rest.skip(1) : rest;
    if (argResults!['set-default'] as bool) {
      ctx.config.defaultAvd = name;
      ctx.saveConfig();
    }
    final timeout = Duration(
      seconds: int.tryParse(argResults!['timeout'] as String) ?? 300,
    );
    final wait = argResults!['wait'] as bool;

    final running = (await tools.runningEmulators())
        .where((e) => e.avdName == name)
        .firstOrNull;
    if (running != null) {
      logger.info('$name is already running as ${running.serial}.');
      if (wait) return _waitForBoot(tools, name, timeout);
      return ExitCode.success.code;
    }

    if (ctx.host.isLinux && !File('/dev/kvm').existsSync()) {
      logger.warn(
        '/dev/kvm is missing: the emulator will run without acceleration '
        '(very slow). See `droidkit doctor`.',
      );
    }

    final args = [
      if (argResults!['cold'] as bool) '-no-snapshot-load',
      if (argResults!['wipe'] as bool) '-wipe-data',
      if (argResults!['headless'] as bool) ...[
        '-no-window',
        '-no-audio',
        '-no-boot-anim',
      ],
      if (argResults!['gpu'] case final String gpu) ...['-gpu', gpu],
      ...extra,
    ];
    final logFile = p.join(ctx.paths.logDir, '$name.log');
    Directory(ctx.paths.logDir).createSync(recursive: true);
    File(logFile).writeAsStringSync(
      '--- droidkit start ${DateTime.now().toIso8601String()} ---\n',
    );
    await tools.startEmulator(name, args, logFile: logFile);

    final progress = Task(logger, 'Starting $name');
    final serial = await _awaitAppearance(tools, name, logFile);
    if (serial == null) {
      progress.fail('$name did not start');
      final problems = _logProblems(logFile);
      if (problems.isNotEmpty) logger.err(problems.join('\n'));
      logger.info('Full log: $logFile');
      return ExitCode.software.code;
    }
    progress.complete('$name is running as $serial');
    if (wait) return _waitForBoot(tools, name, timeout);
    logger.detail('Emulator log: $logFile');
    return ExitCode.success.code;
  }

  String _pickAvd(DroidkitContext ctx, List<String> avds) {
    if (rest.isNotEmpty && avds.contains(rest.first)) return rest.first;
    if (rest.isNotEmpty && !rest.first.startsWith('-')) {
      throw DroidkitException(
        'No emulator named "${rest.first}".',
        hint: 'Available: ${avds.join(', ')}',
        exitCode: ExitCode.usage,
      );
    }
    final fallback = avds.contains(ctx.config.defaultAvd)
        ? ctx.config.defaultAvd!
        : avds.first;
    return ctx.choose('Which emulator?', choices: avds, defaultValue: fallback);
  }

  /// Waits for the emulator to register with adb, or for it to die.
  Future<String?> _awaitAppearance(
    AndroidTools tools,
    String name,
    String logFile,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final match = (await tools.runningEmulators())
          .where((e) => e.avdName == name)
          .firstOrNull;
      if (match != null) return match.serial;
      if (_logProblems(logFile).any((l) => l.contains('FATAL'))) return null;
      // Without adb we can't observe it; assume it's starting.
      if (!tools.sdk.hasPlatformTools) return 'emulator';
    }
    return null;
  }

  static List<String> _logProblems(String logFile) {
    try {
      return File(logFile)
          .readAsLinesSync()
          .where((l) => RegExp(r'\b(FATAL|ERROR|PANIC)\b').hasMatch(l))
          .take(10)
          .toList();
    } on FileSystemException {
      return [];
    }
  }

  Future<int> _waitForBoot(
    AndroidTools tools,
    String name,
    Duration timeout,
  ) async {
    final progress = Task(logger, 'Waiting for Android to boot');
    final serial = await tools.waitForBoot(name, timeout: timeout);
    if (serial == null) {
      progress.fail(
        '$name did not finish booting within ${timeout.inSeconds}s',
      );
      return ExitCode.tempFail.code;
    }
    progress.complete('$name has booted ($serial)');
    return ExitCode.success.code;
  }
}
