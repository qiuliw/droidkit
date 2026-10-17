import 'package:droidkit/droidkit.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pub_updater/pub_updater.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockPubUpdater extends Mock implements PubUpdater {}

void main() {
  late Logger logger;
  late DroidkitCommandRunner runner;

  setUp(() {
    logger = _MockLogger();
    when(() => logger.level).thenReturn(Level.info);
    runner = DroidkitCommandRunner(
      logger: logger,
      pubUpdater: _MockPubUpdater(),
      environment: {'HOME': '/tmp', 'CI': 'true'},
    );
  });

  test('--version prints the version', () async {
    expect(await runner.run(['--version']), ExitCode.success.code);
    verify(() => logger.info(packageVersion)).called(1);
  });

  test('unknown commands are usage errors', () async {
    expect(await runner.run(['frobnicate']), ExitCode.usage.code);
    verify(() => logger.err(any(that: contains('frobnicate')))).called(1);
  });

  test('bad option values are usage errors', () async {
    expect(await runner.run(['start', '--gpu', 'banana']), ExitCode.usage.code);
  });

  test('every command has a description', () {
    for (final command in runner.commands.values) {
      expect(command.description, isNotEmpty, reason: command.name);
    }
    expect(
      runner.commands.keys,
      containsAll([
        'setup',
        'doctor',
        'start',
        'stop',
        'list',
        'avd',
        'images',
        'sdk',
        'jdk',
        'licenses',
        'env',
        'clean',
      ]),
    );
  });
}
