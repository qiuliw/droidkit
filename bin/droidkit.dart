import 'dart:async';
import 'dart:io';

import 'package:droidkit/droidkit.dart';

Future<void> main(List<String> args) async {
  await runZonedGuarded(
    () async {
      final code = await DroidkitCommandRunner().run(args);
      await _flush();
      exit(code);
    },
    (error, stack) {
      // `droidkit … | head` closes the pipe early; that's not an error.
      if (_isBrokenPipe(error)) exit(0);
      stderr
        ..writeln('Unexpected error: $error')
        ..writeln(stack);
      exit(70);
    },
  );
}

bool _isBrokenPipe(Object error) =>
    (error is FileSystemException && error.osError?.errorCode == 32) ||
    (error is SocketException && error.osError?.errorCode == 32) ||
    (error is StdoutException);

Future<void> _flush() async {
  try {
    await Future.wait<void>([stdout.close(), stderr.close()]);
  } on Object {
    // Pipe already closed.
  }
}
