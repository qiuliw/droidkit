import 'package:droidkit/src/commands/droidkit_command.dart';
import 'package:droidkit/src/context.dart';
import 'package:droidkit/src/tools/android_tools.dart';
import 'package:mason_logger/mason_logger.dart';

/// `droidkit stop`.
class StopCommand extends DroidkitCommand {
  /// Creates a [StopCommand].
  StopCommand(super.context) {
    argParser.addFlag(
      'all',
      abbr: 'a',
      negatable: false,
      help: 'Stop every running emulator.',
    );
  }

  @override
  String get name => 'stop';

  @override
  String get description => 'Shut down a running emulator.';

  @override
  String get invocation => 'droidkit stop [<name> | --all]';

  @override
  Future<int> run() async {
    maxArgs(1);
    final ctx = await context();
    final sdk = await ctx.sdk();
    if (!sdk.hasPlatformTools) {
      throw DroidkitException(
        'adb (platform-tools) is not installed.',
        hint: 'Run `droidkit sdk install platform-tools`.',
      );
    }
    final tools = await ctx.tools(sdk, needJava: false);
    final running = await tools.runningEmulators();
    if (running.isEmpty) {
      logger.info('No emulators are running.');
      return ExitCode.success.code;
    }

    List<RunningEmulator> targets;
    if (argResults!['all'] as bool) {
      targets = running;
    } else if (rest.isNotEmpty) {
      final name = rest.single;
      targets = running
          .where((e) => e.avdName == name || e.serial == name)
          .toList();
      if (targets.isEmpty) {
        throw DroidkitException(
          '"$name" is not running.',
          hint: 'Running: ${running.map(_label).join(', ')}',
          exitCode: ExitCode.usage,
        );
      }
    } else {
      targets = [
        ctx.choose(
          'Which emulator should stop?',
          choices: running,
          defaultValue: running.first,
          display: _label,
        ),
      ];
    }

    var failed = false;
    for (final e in targets) {
      final result = await tools.killEmulator(e.serial);
      if (result.ok) {
        logger.success('Stopped ${_label(e)}');
      } else {
        failed = true;
        logger.err('Could not stop ${_label(e)}: ${result.stderr.trim()}');
      }
    }
    return failed ? ExitCode.software.code : ExitCode.success.code;
  }

  static String _label(RunningEmulator e) =>
      e.avdName == null ? e.serial : '${e.avdName} (${e.serial})';
}
