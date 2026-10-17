import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:droidkit/src/catalog/catalog_repository.dart';
import 'package:droidkit/src/commands/avd_command.dart';
import 'package:droidkit/src/commands/clean_command.dart';
import 'package:droidkit/src/commands/doctor_command.dart';
import 'package:droidkit/src/commands/env_command.dart';
import 'package:droidkit/src/commands/images_command.dart';
import 'package:droidkit/src/commands/jdk_command.dart';
import 'package:droidkit/src/commands/licenses_command.dart';
import 'package:droidkit/src/commands/sdk_command.dart';
import 'package:droidkit/src/commands/setup_command.dart';
import 'package:droidkit/src/commands/start_command.dart';
import 'package:droidkit/src/commands/stop_command.dart';
import 'package:droidkit/src/config/droidkit_config.dart';
import 'package:droidkit/src/context.dart';
import 'package:droidkit/src/host/host_platform.dart';
import 'package:droidkit/src/net/downloader.dart';
import 'package:droidkit/src/process/process_runner.dart';
import 'package:droidkit/src/tools/flutter_tool.dart';
import 'package:droidkit/src/version.dart';
import 'package:file/local.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:pub_updater/pub_updater.dart';

/// The executable name.
const executableName = 'droidkit';

/// The pub.dev package name.
const packageName = 'droidkit';

/// droidkit's command runner.
class DroidkitCommandRunner extends CompletionCommandRunner<int> {
  /// Creates a [DroidkitCommandRunner].
  DroidkitCommandRunner({
    Logger? logger,
    ProcessRunner processRunner = const ProcessRunner(),
    PubUpdater? pubUpdater,
    Map<String, String>? environment,
  }) : _logger = logger ?? Logger(),
       _processRunner = processRunner,
       _pubUpdater = pubUpdater ?? PubUpdater(),
       _environment = environment ?? Platform.environment,
       super(
         executableName,
         'Set up the Android SDK, a JDK and emulators for Flutter — '
         'no Android Studio needed.',
       ) {
    argParser
      ..addFlag(
        'version',
        negatable: false,
        help: 'Print the droidkit version.',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Show detailed output.',
      )
      ..addFlag(
        'yes',
        abbr: 'y',
        negatable: false,
        help:
            'Answer yes to every question, including accepting the '
            'Android SDK licenses. Needed for unattended/CI runs.',
      )
      ..addOption(
        'sdk-root',
        help:
            'Android SDK directory to use or create (overrides '
            'ANDROID_HOME).',
        valueHelp: 'path',
      );

    Future<DroidkitContext> context() => _buildContext();
    addCommand(SetupCommand(context));
    addCommand(DoctorCommand(context));
    addCommand(StartCommand(context));
    addCommand(StopCommand(context));
    addCommand(AvdListCommand(context, alias: true));
    addCommand(AvdCommand(context));
    addCommand(ImagesCommand(context));
    addCommand(SdkCommand(context));
    addCommand(JdkCommand(context));
    addCommand(LicensesCommand(context));
    addCommand(EnvCommand(context));
    addCommand(CleanCommand(context));
  }

  final Logger _logger;
  final ProcessRunner _processRunner;
  final PubUpdater _pubUpdater;
  final Map<String, String> _environment;
  ArgResults? _globalResults;
  DroidkitContext? _context;

  @override
  void printUsage() => _logger.info(usage);

  // Never edit the user's shell files unasked; completions are opt-in via
  // `droidkit install-completion-files`.
  @override
  bool get enableAutoInstall => false;

  Future<DroidkitContext> _buildContext() async {
    if (_context != null) return _context!;
    final results = _globalResults;
    final host = await HostPlatform.detect(
      runner: _processRunner,
      environment: _environment,
    );
    final paths = DroidkitPaths.fromEnvironment(
      _environment,
      host.homeDirectory,
    );
    final downloader = Downloader();
    final assumeYes = results?['yes'] == true;
    final sdkRoot = results?['sdk-root'] as String?;
    return _context = DroidkitContext(
      logger: _logger,
      fs: const LocalFileSystem(),
      runner: _processRunner,
      host: host,
      paths: paths,
      downloader: downloader,
      catalogs: CatalogRepository(
        downloader: downloader,
        cacheDir: paths.cacheDir,
      ),
      flutter: FlutterTool(_processRunner),
      assumeYes: assumeYes,
      interactive: stdin.hasTerminal && stdout.hasTerminal && !host.isCi,
      sdkRootOverride: sdkRoot == null
          ? null
          : p.normalize(p.absolute(_expandHome(sdkRoot, host))),
    );
  }

  static String _expandHome(String path, HostPlatform host) =>
      path == '~' || path.startsWith('~/') || path.startsWith(r'~\')
      ? host.homeDirectory + path.substring(1)
      : path;

  @override
  Future<int> run(Iterable<String> args) async {
    StreamSubscription<ProcessSignal>? sigint;
    try {
      final results = parse(args);
      _globalResults = results;
      if (results['verbose'] == true) _logger.level = Level.verbose;
      sigint = ProcessSignal.sigint.watch().listen((_) => _onInterrupt());
      final code = await runCommand(results) ?? ExitCode.success.code;
      await _checkForUpdates(results);
      return code;
    } on FormatException catch (e) {
      _logger
        ..err(e.message)
        ..info('')
        ..info(usage);
      return ExitCode.usage.code;
    } on UsageException catch (e) {
      _logger
        ..err(e.message)
        ..info('')
        ..info(e.usage);
      return ExitCode.usage.code;
    } on DroidkitException catch (e) {
      _logger.err(e.message);
      if (e.hint != null) _logger.info(e.hint);
      return (e.exitCode ?? ExitCode.software).code;
    } on DownloadException catch (e) {
      _logger.err(e.message);
      return ExitCode.tempFail.code;
    } on Exception catch (e, stack) {
      _logger
        ..err('Unexpected error: $e')
        ..detail('$stack')
        ..info(
          'Please report this at '
          'https://github.com/sawongam/droidkit/issues (run with --verbose '
          'for details).',
        );
      return ExitCode.software.code;
    } finally {
      await sigint?.cancel();
      _context?.downloader.close();
    }
  }

  void _onInterrupt() {
    _logger.info('\nInterrupted; cleaning up temporary files…');
    final ctx = _context;
    if (ctx != null) {
      final tmp = Directory(ctx.paths.tmpDir);
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } on FileSystemException {
        // Best effort.
      }
    }
    exit(130);
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults.command?.name == 'completion') {
      await super.runCommand(topLevelResults);
      return ExitCode.success.code;
    }
    if (topLevelResults['version'] == true) {
      _logger.info(packageVersion);
      return ExitCode.success.code;
    }
    return super.runCommand(topLevelResults);
  }

  Future<void> _checkForUpdates(ArgResults results) async {
    if (results.command?.name == 'completion' ||
        !stdout.hasTerminal ||
        _environment['CI'] != null ||
        _environment['DROIDKIT_NO_UPDATE_CHECK'] != null) {
      return;
    }
    final ctx = _context;
    if (ctx == null) return;
    // At most once a day.
    final stamp = File(p.join(ctx.paths.cacheDir, 'last_update_check'));
    if (stamp.existsSync() &&
        DateTime.now().difference(stamp.lastModifiedSync()) <
            const Duration(days: 1)) {
      return;
    }
    try {
      final latest = await _pubUpdater
          .getLatestVersion(packageName)
          .timeout(const Duration(seconds: 3));
      stamp.parent.createSync(recursive: true);
      stamp.writeAsStringSync(latest);
      if (latest != packageVersion) {
        _logger
          ..info('')
          ..info(
            '${lightYellow.wrap('Update available!')} '
            '${lightCyan.wrap(packageVersion)} → ${lightCyan.wrap(latest)}\n'
            'Run ${lightCyan.wrap('dart pub global activate $packageName')} '
            'to update.',
          );
      }
    } on Object {
      // Offline or pub.dev unreachable: never fail the command for this.
    }
  }
}
