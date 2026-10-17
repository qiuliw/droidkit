import 'dart:io';

import 'package:droidkit/src/commands/droidkit_command.dart';
import 'package:droidkit/src/context.dart';
import 'package:droidkit/src/env/shell_profile.dart';
import 'package:mason_logger/mason_logger.dart';

/// Builds the environment droidkit recommends for [ctx].
Future<ToolchainEnvironment> toolchainEnvironment(DroidkitContext ctx) async {
  final sdk = await ctx.sdk();
  final jdk = await ctx.jdk();
  return ToolchainEnvironment(
    sdkRoot: sdk.root,
    // A java already on PATH works without JAVA_HOME; don't pin it.
    javaHome: jdk == null || jdk.source == 'PATH' ? null : jdk.home,
  );
}

/// Persists [env] for [shell]; returns a message describing what changed.
Future<String> persistEnvironment(
  DroidkitContext ctx,
  Shell shell,
  ToolchainEnvironment env,
) async {
  if (ctx.host.isWindows) {
    final r = await ctx.runner.run('powershell', [
      '-NoProfile',
      '-Command',
      ShellProfile.windowsPersistScript(env),
    ]);
    if (!r.ok) {
      throw DroidkitException(
        'Could not set user environment variables: ${r.stderr.trim()}',
      );
    }
    return 'Saved ANDROID_HOME${env.javaHome != null ? ', JAVA_HOME' : ''} and '
        'PATH as user environment variables. Open a new terminal to use them.';
  }
  final file = ShellProfile(ctx.host, ctx.fs).persist(shell, env);
  return 'Updated $file. Open a new terminal (or run `source $file`).';
}

/// `droidkit env`.
class EnvCommand extends DroidkitCommand {
  /// Creates an [EnvCommand].
  EnvCommand(super.context) {
    argParser
      ..addOption(
        'shell',
        abbr: 's',
        help: 'Shell syntax to print (detected automatically).',
        allowed: Shell.values.map((s) => s.name),
      )
      ..addFlag(
        'persist',
        negatable: false,
        help:
            'Add the environment to your shell profile (or Windows user '
            'environment variables).',
      )
      ..addFlag(
        'unpersist',
        negatable: false,
        help: 'Remove what --persist added.',
      );
  }

  @override
  String get name => 'env';

  @override
  String get description =>
      'Print (or persist) ANDROID_HOME, JAVA_HOME and PATH for your shell. '
      'Use: eval "\$(droidkit env)"';

  @override
  Future<int> run() async {
    maxArgs(0);
    final ctx = await context();
    final shellName = argResults!['shell'] as String?;
    final shell = shellName == null
        ? Shell.detect(ctx.host)
        : Shell.values.byName(shellName);
    final env = await toolchainEnvironment(ctx);
    final persist = argResults!['persist'] as bool;
    final unpersist = argResults!['unpersist'] as bool;
    if (persist && unpersist) {
      usageException('Use either --persist or --unpersist.');
    }

    if (persist) {
      logger.success(await persistEnvironment(ctx, shell, env));
      return ExitCode.success.code;
    }
    if (unpersist) {
      if (ctx.host.isWindows) {
        await ctx.runner.run('powershell', [
          '-NoProfile',
          '-Command',
          ShellProfile.windowsUnpersistScript(env),
        ]);
        logger.success('Removed droidkit\'s user environment variables.');
      } else {
        final removed = ShellProfile(ctx.host, ctx.fs).unpersist(shell);
        logger.info(
          removed
              ? 'Removed droidkit\'s block from '
                    '${ShellProfile(ctx.host, ctx.fs).rcFile(shell)}.'
              : 'Nothing to remove for ${shell.name}.',
        );
      }
      return ExitCode.success.code;
    }

    // Plain output goes to stdout so it can be eval'd.
    stdout.writeln(env.render(shell));
    if (stdout.hasTerminal) {
      final hint = switch (shell) {
        Shell.fish => 'droidkit env | source',
        Shell.powershell => 'droidkit env | Out-String | Invoke-Expression',
        Shell.cmd => 'droidkit env --persist',
        _ => 'eval "\$(droidkit env)"',
      };
      stderr.writeln(
        darkGray.wrap(
          '\n# Apply now with: $hint\n'
          '# Make permanent with: droidkit env --persist',
        ),
      );
    }
    return ExitCode.success.code;
  }
}
