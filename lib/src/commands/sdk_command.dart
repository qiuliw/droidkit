import 'package:args/command_runner.dart';
import 'package:droidkit/src/catalog/models.dart';
import 'package:droidkit/src/catalog/resolver.dart';
import 'package:droidkit/src/commands/droidkit_command.dart';
import 'package:droidkit/src/context.dart';
import 'package:droidkit/src/ui/task.dart';
import 'package:droidkit/src/util.dart';
import 'package:mason_logger/mason_logger.dart';

/// `droidkit sdk`.
class SdkCommand extends Command<int> {
  /// Creates an [SdkCommand].
  SdkCommand(ContextProvider context) {
    addSubcommand(_SdkListCommand(context));
    addSubcommand(_SdkInstallCommand(context));
    addSubcommand(_SdkUninstallCommand(context));
    addSubcommand(_SdkUpdateCommand(context));
  }

  @override
  String get name => 'sdk';

  @override
  String get description => 'List, install, remove and update SDK packages.';
}

class _SdkListCommand extends DroidkitCommand {
  _SdkListCommand(super.context) {
    argParser
      ..addFlag(
        'available',
        abbr: 'a',
        negatable: false,
        help: 'Show packages available to install instead of installed ones.',
      )
      ..addFlag(
        'all',
        negatable: false,
        help:
            'With --available: include previews, obsolete and '
            'system-image packages.',
      )
      ..addOption(
        'filter',
        abbr: 'f',
        help: 'Only show packages whose path contains this text.',
      );
  }

  @override
  String get name => 'list';

  @override
  String get description => 'List installed (or available) SDK packages.';

  @override
  Future<int> run() async {
    maxArgs(0);
    final ctx = await context();
    final filter = argResults!['filter'] as String?;
    bool matches(String path) => filter == null || path.contains(filter);

    if (!(argResults!['available'] as bool)) {
      final sdk = await ctx.sdk();
      if (!sdk.exists) {
        throw DroidkitException(
          'No Android SDK at ${sdk.root}.',
          hint: 'Run `droidkit setup`.',
        );
      }
      final installed = sdk.installedPackages().where((i) => matches(i.path));
      logger.info(styleBold.wrap('Installed in ${sdk.root}:'));
      for (final pkg in installed) {
        logger.info('  ${pkg.path.padRight(56)} ${pkg.version}');
      }
      return ExitCode.success.code;
    }

    final all = argResults!['all'] as bool;
    final catalog = await ctx.catalogs.main();
    final sdk = await ctx.sdk();
    final installed = {for (final i in sdk.installedPackages()) i.path};
    final latest = <String, RemotePackage>{};
    for (final pkg in catalog.packages) {
      if (!matches(pkg.path) || pkg.archiveFor(ctx.host) == null) continue;
      if (!all && (pkg.isPreview || pkg.obsolete)) continue;
      final existing = latest[pkg.path];
      if (existing == null || pkg.revision > existing.revision) {
        latest[pkg.path] = pkg;
      }
    }
    // Group by kind (build-tools, platforms…), newest first within a group.
    final sorted = latest.values.toList()
      ..sort((a, b) {
        final kind = a.path.split(';').first.compareTo(b.path.split(';').first);
        return kind != 0 ? kind : b.revision.compareTo(a.revision);
      });
    logger.info(styleBold.wrap('Available packages:'));
    for (final pkg in sorted) {
      final mark = installed.contains(pkg.path) ? green.wrap('✓')! : ' ';
      final size = formatBytes(pkg.sizeFor(ctx.host) ?? 0);
      logger.info(
        '$mark ${pkg.path.padRight(56)} ${pkg.revision.toString().padRight(12)}'
        ' ${darkGray.wrap(size)}',
      );
    }
    logger.detail(
      'System images: `droidkit images`. Install: `droidkit sdk install <path>`.',
    );
    return ExitCode.success.code;
  }
}

class _SdkInstallCommand extends DroidkitCommand {
  _SdkInstallCommand(super.context);

  @override
  String get name => 'install';

  @override
  String get description =>
      'Install SDK packages, e.g. `droidkit sdk install "platforms;android-36"`.';

  @override
  String get invocation => 'droidkit sdk install <package> [<package>...]';

  @override
  Future<int> run() async {
    if (rest.isEmpty) usageException('Name at least one package.');
    final ctx = await context();
    final installer = await this.installer();
    await installer.ensureJdk();
    final sdk = await ctx.sdk();
    await installer.ensureCmdlineTools(sdk);

    final catalog = await ctx.catalogs.main();
    final unknown = rest.where(
      (path) =>
          !path.startsWith('system-images;') &&
          !catalog.packages.any((p) => p.path == path),
    );
    if (unknown.isNotEmpty) {
      throw DroidkitException(
        'Unknown package(s): ${unknown.join(', ')}',
        hint:
            'See `droidkit sdk list --available` (quote paths containing '
            '";" in your shell).',
        exitCode: ExitCode.usage,
      );
    }
    final tools = await ctx.tools(sdk);
    await installer.acceptLicenses(tools);
    await installer.installPackages(tools, rest);
    return ExitCode.success.code;
  }
}

class _SdkUninstallCommand extends DroidkitCommand {
  _SdkUninstallCommand(super.context);

  @override
  String get name => 'uninstall';

  @override
  String get description => 'Remove SDK packages.';

  @override
  String get invocation => 'droidkit sdk uninstall <package> [<package>...]';

  @override
  Future<int> run() async {
    if (rest.isEmpty) usageException('Name at least one package.');
    final ctx = await context();
    final sdk = await ctx.requireSdk();
    final notInstalled = rest.where((path) => !sdk.isInstalled(path)).toList();
    if (notInstalled.isNotEmpty) {
      logger.warn('Not installed: ${notInstalled.join(', ')}');
    }
    final targets = rest.where(sdk.isInstalled).toList();
    if (targets.isEmpty) return ExitCode.success.code;
    if (!ctx.confirm('Remove ${targets.join(', ')}?')) {
      return ExitCode.success.code;
    }
    final code = await (await ctx.tools(sdk)).uninstall(targets);
    if (code == 0) logger.success('Removed ${targets.join(', ')}');
    return code == 0 ? ExitCode.success.code : ExitCode.software.code;
  }
}

class _SdkUpdateCommand extends DroidkitCommand {
  _SdkUpdateCommand(super.context);

  @override
  String get name => 'update';

  @override
  String get description => 'Update every installed SDK package.';

  @override
  Future<int> run() async {
    maxArgs(0);
    final ctx = await context();
    final sdk = await ctx.requireSdk();
    final tools = await ctx.tools(sdk);
    await (await installer()).acceptLicenses(tools);
    final progress = Task(logger, 'Updating SDK packages');
    final code = await tools.update(
      onLine: (line) {
        if (line.trim().isNotEmpty) progress.update(line.trim());
      },
    );
    if (code == 0) {
      progress.complete('SDK packages are up to date');
      final major = sdk.cmdlineToolsMajor;
      if (major != null &&
          major >= 23 &&
          await ctx.flutter.executable() != null) {
        logger.warn(
          'cmdline-tools ${sdk.cmdlineToolsVersion} makes `flutter doctor` '
          'report "Android license status unknown". Run `droidkit doctor '
          '--fix` to switch back to $flutterCompatibleCmdlineTools.',
        );
      }
      return ExitCode.success.code;
    }
    progress.fail('sdkmanager --update failed (exit $code)');
    return ExitCode.software.code;
  }
}
