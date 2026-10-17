import 'dart:io';

import 'package:mason_logger/mason_logger.dart';

/// A long-running step shown to the user.
///
/// On a terminal this is an animated spinner (mason_logger [Progress]); when
/// output is redirected (CI logs, pipes) it prints one line when the step
/// starts and one when it ends, instead of hundreds of spinner frames.
class Task {
  /// Starts a task with [message].
  Task(this._logger, String message, {bool? terminal})
    : _terminal = terminal ?? stdout.hasTerminal {
    if (_terminal) {
      _progress = _logger.progress(message);
    } else {
      _logger.info('• $message…');
    }
  }

  final Logger _logger;
  final bool _terminal;
  Progress? _progress;

  /// Updates the message (ignored when not on a terminal).
  void update(String message) => _progress?.update(message);

  /// Marks the task as done.
  void complete([String? message]) {
    if (_progress != null) {
      _progress!.complete(message);
    } else if (message != null) {
      _logger.success('✓ $message');
    }
  }

  /// Marks the task as failed.
  void fail([String? message]) {
    if (_progress != null) {
      _progress!.fail(message);
    } else if (message != null) {
      _logger.err('✗ $message');
    }
  }

  /// Removes the spinner without a result line.
  void cancel() => _progress?.cancel();
}
