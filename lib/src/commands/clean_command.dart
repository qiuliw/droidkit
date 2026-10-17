import 'dart:io';

import 'package:droidkit/src/commands/droidkit_command.dart';
import 'package:droidkit/src/commands/env_command.dart';
import 'package:droidkit/src/env/shell_profile.dart';
import 'package:mason_logger/mason_logger.dart';

/// `droidkit clean`.
class CleanCommand extends DroidkitCommand {
  /// Creates a [CleanCommand].
  CleanCommand(super.context) {
    argParser.addFlag(
      'all',
      negatable: false,
      help:
          'Also remove droidkit\'s JDKs, its shell profile block, and the '
          'Android SDK if droidkit created it.',
    );
  }

  @override
  String get name => 'clean';

  @override
  String get description => 'Remove droidkit caches and temporary downloads.';

  @override
  Future<int> run() async {
    maxArgs(0);
    final ctx = await context();
    final paths = ctx.paths;
    void remove(String path, String label) {
      final dir = Directory(path);
      if (!dir.existsSync()) return;
      dir.deleteSync(recursive: true);
      logger.success('Removed $label ($path)');
    }

    remove(paths.tmpDir, 'temporary downloads');
    remove(paths.cacheDir, 'catalog cache');
    remove(paths.logDir, 'emulator logs');
    if (!(argResults!['all'] as bool)) return ExitCode.success.code;

    final sdkRoot = ctx.config.sdkRoot;
    final managed = ctx.config.managedSdk && sdkRoot != null;
    final lines = [
      styleBold.wrap('This will remove:')!,
      '  • droidkit JDKs in ${paths.jdkDir}',
      if (managed) '  • the Android SDK droidkit installed at $sdkRoot',
      "  • droidkit's shell environment setup",
      '  • droidkit settings (${paths.configFile})',
      if (!managed && sdkRoot != null)
        '(The SDK at $sdkRoot was not created by droidkit and is kept.)',
      'Emulators in ~/.android/avd are kept; delete them with '
          '`droidkit avd delete`.',
    ];
    logger.info(lines.join('\n'));
    if (!ctx.confirm('Continue?', defaultValue: false)) {
      return ExitCode.success.code;
    }
    remove(paths.jdkDir, 'droidkit JDKs');
    if (managed) remove(sdkRoot, 'Android SDK');
    if (ctx.host.isWindows) {
      await ctx.runner.run('powershell', [
        '-NoProfile',
        '-Command',
        ShellProfile.windowsUnpersistScript(await toolchainEnvironment(ctx)),
      ]);
      logger.success('Removed droidkit user environment variables');
    } else {
      final profile = ShellProfile(ctx.host, ctx.fs);
      for (final shell in [Shell.bash, Shell.zsh, Shell.fish]) {
        if (profile.unpersist(shell)) {
          logger.success('Removed block from ${profile.rcFile(shell)}');
        }
      }
    }
    final config = File(paths.configFile);
    if (config.existsSync()) config.deleteSync();
    logger.info(
      'Done. Uninstall droidkit itself with `dart pub global deactivate '
      'droidkit`.',
    );
    return ExitCode.success.code;
  }
}
