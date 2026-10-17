import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The outcome of a finished process.
class RunResult {
  /// Creates a [RunResult].
  const RunResult(this.exitCode, this.stdout, this.stderr);

  /// The process exit code.
  final int exitCode;

  /// Everything the process wrote to stdout.
  final String stdout;

  /// Everything the process wrote to stderr.
  final String stderr;

  /// Whether the process exited with code 0.
  bool get ok => exitCode == 0;
}

/// Runs external programs. Injected everywhere so commands can be tested
/// without touching the real system.
class ProcessRunner {
  /// Creates a [ProcessRunner].
  const ProcessRunner();

  /// Whether [executable] needs a shell to run (Windows `.bat`/`.cmd`).
  static bool _needsShell(String executable) {
    final lower = executable.toLowerCase();
    return Platform.isWindows &&
        (lower.endsWith('.bat') || lower.endsWith('.cmd'));
  }

  /// Makes [arguments] survive `cmd.exe` when running a `.bat` file.
  ///
  /// The SDK scripts forward `%*` untouched, so `;`, `,` and `=` (as in
  /// `platforms;android-36` or `--sdk_root=C:\Sdk`) need no help. Quoting
  /// them ourselves breaks things: with `runInShell` Dart turns every `"`
  /// into `\"`, which reaches sdkmanager as literal characters. What cmd
  /// itself would interpret (`&|<>^()`) is caret-escaped instead, unless
  /// Dart already wraps the argument in quotes (it has spaces or tabs).
  static List<String> cmdSafeArguments(List<String> arguments) => [
    for (final arg in arguments)
      if (arg.contains(RegExp(r'[ \t"]')))
        arg
      else
        arg.replaceAllMapped(RegExp(r'[&|<>^()]'), (m) => '^${m[0]}'),
  ];

  static List<String> _args(String executable, List<String> arguments) =>
      _needsShell(executable) ? cmdSafeArguments(arguments) : arguments;

  /// Runs [executable] to completion and captures its output.
  ///
  /// When [stdinLines] is given, each line is written to the process stdin
  /// (useful for answering prompts such as license questions).
  Future<RunResult> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? workingDirectory,
    Iterable<String>? stdinLines,
    Duration? timeout,
  }) async {
    final Process process;
    try {
      process = await Process.start(
        executable,
        _args(executable, arguments),
        environment: environment,
        workingDirectory: workingDirectory,
        runInShell: _needsShell(executable),
      );
    } on ProcessException catch (e) {
      return RunResult(127, '', e.message);
    }
    final out = process.stdout.transform(systemEncoding.decoder).join();
    final err = process.stderr.transform(systemEncoding.decoder).join();
    if (stdinLines != null) {
      try {
        for (final line in stdinLines) {
          process.stdin.writeln(line);
        }
        await process.stdin.flush();
      } on Object {
        // The process may exit before reading everything; that's fine.
      }
    }
    unawaited(process.stdin.close().catchError((Object _) {}));
    var exitFuture = process.exitCode;
    if (timeout != null) {
      exitFuture = exitFuture.timeout(
        timeout,
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
    }
    final code = await exitFuture;
    return RunResult(code, await out, await err);
  }

  /// Runs [executable] with the terminal attached, so the user sees output
  /// and can answer prompts. Returns the exit code.
  ///
  /// When [autoAnswer] is set, it is written repeatedly to stdin instead of
  /// forwarding the user's keyboard (used for `--yes` license acceptance).
  Future<int> runInteractive(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? autoAnswer,
    void Function(String line)? onLine,
  }) async {
    final Process process;
    try {
      process = await Process.start(
        executable,
        _args(executable, arguments),
        environment: environment,
        runInShell: _needsShell(executable),
        mode: autoAnswer == null && onLine == null
            ? ProcessStartMode.inheritStdio
            : ProcessStartMode.normal,
      );
    } on ProcessException catch (e) {
      stderr.writeln(e.message);
      return 127;
    }
    if (autoAnswer == null && onLine == null) return process.exitCode;

    final done = <Future<void>>[];
    void pipe(Stream<List<int>> stream, IOSink sink) {
      if (onLine == null) {
        done.add(stream.forEach(sink.add));
      } else {
        done.add(
          stream
              .transform(systemEncoding.decoder)
              .transform(const LineSplitter())
              .forEach(onLine),
        );
      }
    }

    pipe(process.stdout, stdout);
    pipe(process.stderr, stderr);
    if (autoAnswer != null) {
      // Answer every prompt; the process exits once it has what it needs.
      Timer? timer;
      // A write into a pipe the process already closed fails asynchronously
      // on `done`, not in writeln; unobserved, it would crash droidkit.
      unawaited(
        process.stdin.done.catchError((Object _) {
          timer?.cancel();
        }),
      );
      timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        try {
          process.stdin.writeln(autoAnswer);
        } on Object {
          // stdin closed.
        }
      });
      final code = await process.exitCode;
      timer.cancel();
      await Future.wait(done);
      return code;
    } else {
      unawaited(stdin.pipe(process.stdin).catchError((Object _) {}));
    }
    final code = await process.exitCode;
    await Future.wait(done);
    return code;
  }

  /// Starts [executable] fully detached from droidkit (it keeps running after
  /// droidkit exits). Returns the pid.
  ///
  /// On macOS/Linux, output is appended to [logFile] when given, so failures
  /// of the detached process can still be diagnosed.
  Future<int> startDetached(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? logFile,
  }) async {
    if (logFile != null && !Platform.isWindows) {
      final process = await Process.start(
        '/bin/sh',
        [
          '-c',
          r'log="$1"; shift; exec "$@" >>"$log" 2>&1 </dev/null',
          'droidkit',
          logFile,
          executable,
          ...arguments,
        ],
        environment: environment,
        mode: ProcessStartMode.detached,
      );
      return process.pid;
    }
    final process = await Process.start(
      executable,
      _args(executable, arguments),
      environment: environment,
      runInShell: _needsShell(executable),
      mode: ProcessStartMode.detached,
    );
    return process.pid;
  }

  /// Returns the full path of [command] on PATH, or null.
  ///
  /// On Windows, `where flutter` lists the extension-less bash script before
  /// `flutter.bat`; only real executables are returned.
  Future<String?> which(String command) async {
    final result = await run(Platform.isWindows ? 'where' : 'which', [command]);
    if (!result.ok) return null;
    final lines = LineSplitter.split(
      result.stdout,
    ).map((l) => l.trim()).where((l) => l.isNotEmpty);
    if (!Platform.isWindows) return lines.firstOrNull;
    return lines
        .where(
          (l) => RegExp(r'\.(exe|bat|cmd)$', caseSensitive: false).hasMatch(l),
        )
        .firstOrNull;
  }
}
