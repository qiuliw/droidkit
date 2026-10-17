import 'package:droidkit/src/process/process_runner.dart';
import 'package:test/test.dart';

void main() {
  test('auto-answering survives a process that closes its stdin', () async {
    // Closes stdin, then stays alive so the periodic answers hit a dead
    // pipe (sdkmanager does this once it stops reading).
    final code = await const ProcessRunner().runInteractive(
      '/bin/sh',
      ['-c', 'exec 0<&-; sleep 1'],
      autoAnswer: 'y',
      onLine: (_) {},
    );
    expect(code, 0);
  }, testOn: '!windows');
}
