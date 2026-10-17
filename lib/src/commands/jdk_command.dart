import 'package:args/command_runner.dart';
import 'package:droidkit/src/commands/droidkit_command.dart';
import 'package:droidkit/src/java/jdk.dart';
import 'package:mason_logger/mason_logger.dart';

/// `droidkit jdk`.
class JdkCommand extends Command<int> {
  /// Creates a [JdkCommand].
  JdkCommand(ContextProvider context) {
    addSubcommand(_JdkInstallCommand(context));
    addSubcommand(_JdkListCommand(context));
  }

  @override
  String get name => 'jdk';

  @override
  String get description => 'Manage the Java JDK used by the Android tools.';
}

class _JdkInstallCommand extends DroidkitCommand {
  _JdkInstallCommand(super.context) {
    argParser.addOption(
      'version',
      help: 'JDK major version ($minJavaVersion–$maxJavaVersion).',
      defaultsTo: '$defaultJavaVersion',
    );
  }

  @override
  String get name => 'install';

  @override
  String get description =>
      'Download Eclipse Temurin into ~/.droidkit/jdk (system Java is not '
      'touched).';

  @override
  Future<int> run() async {
    maxArgs(0);
    final ctx = await context();
    final major = int.tryParse(argResults!['version'] as String);
    if (major == null || major < minJavaVersion || major > maxJavaVersion) {
      usageException(
        '--version must be between $minJavaVersion and $maxJavaVersion.',
      );
    }
    final jdk = await (await installer()).installJdk(major);
    logger
      ..success('JDK ${jdk.versionString} ready at ${jdk.home}')
      ..info(
        'droidkit will use it automatically. For Flutter, run '
        '`droidkit setup` or `flutter config --jdk-dir "${jdk.home}"`.',
      );
    ctx.config.jdkHome = jdk.home;
    ctx.saveConfig();
    return ExitCode.success.code;
  }
}

class _JdkListCommand extends DroidkitCommand {
  _JdkListCommand(super.context);

  @override
  String get name => 'list';

  @override
  String get description => 'Show every JDK droidkit can find.';

  @override
  Future<int> run() async {
    maxArgs(0);
    final ctx = await context();
    final flutterJdk = (await ctx.flutter.config())['jdk-dir'];
    final all = await ctx.jdkLocator.findAll(
      configured: ctx.config.jdkHome,
      flutterJdkDir: flutterJdk,
    );
    if (all.isEmpty) {
      logger.info('No JDKs found. Run `droidkit jdk install`.');
      return ExitCode.success.code;
    }
    final best = all.where((j) => j.isSupported).firstOrNull;
    for (final jdk in all) {
      final marker = identical(jdk, best) ? green.wrap('*')! : ' ';
      final status = jdk.isSupported ? '' : red.wrap('  (${jdk.problem})')!;
      logger.info(
        '$marker Java ${jdk.majorVersion} (${jdk.versionString})  '
        '${jdk.home}  ${darkGray.wrap('[${jdk.source}]')}$status',
      );
    }
    if (best != null) logger.detail('* = the JDK droidkit uses');
    return ExitCode.success.code;
  }
}
