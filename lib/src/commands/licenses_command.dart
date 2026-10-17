import 'package:droidkit/src/commands/droidkit_command.dart';
import 'package:mason_logger/mason_logger.dart';

/// `droidkit licenses`.
class LicensesCommand extends DroidkitCommand {
  /// Creates a [LicensesCommand].
  LicensesCommand(super.context) {
    argParser.addFlag(
      'show',
      negatable: false,
      help: 'Print the license texts without accepting anything.',
    );
  }

  @override
  String get name => 'licenses';

  @override
  String get description => 'Review and accept the Android SDK licenses.';

  @override
  Future<int> run() async {
    maxArgs(0);
    final ctx = await context();
    if (argResults!['show'] as bool) {
      final catalog = await ctx.catalogs.main();
      for (final license in catalog.licenses.values) {
        logger
          ..info(styleBold.wrap('── ${license.id} ──'))
          ..info(license.text.trim())
          ..info('');
      }
      return ExitCode.success.code;
    }
    final installer = await this.installer();
    await installer.ensureJdk();
    final sdk = await ctx.sdk();
    await installer.ensureCmdlineTools(sdk);
    if (installer.licensesAccepted(sdk)) {
      logger.success('The Android SDK licenses are already accepted.');
      return ExitCode.success.code;
    }
    await installer.acceptLicenses(await ctx.tools(sdk));
    logger.success('Licenses accepted.');
    return ExitCode.success.code;
  }
}
