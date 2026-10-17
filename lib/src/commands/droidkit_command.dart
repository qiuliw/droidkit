import 'package:args/command_runner.dart';
import 'package:droidkit/src/context.dart';
import 'package:droidkit/src/installer.dart';
import 'package:mason_logger/mason_logger.dart';

/// Signature of the factory that builds a [DroidkitContext] from global flags.
typedef ContextProvider = Future<DroidkitContext> Function();

/// Base class for droidkit commands.
abstract class DroidkitCommand extends Command<int> {
  /// Creates a [DroidkitCommand].
  DroidkitCommand(this._context);

  final ContextProvider _context;

  DroidkitContext? _ctx;

  /// Shared services (built lazily, after global flags are parsed).
  Future<DroidkitContext> context() async => _ctx ??= await _context();

  /// The logger (only valid after [context] was awaited).
  Logger get logger => _ctx!.logger;

  /// Installer bound to the context.
  Future<Installer> installer() async => Installer(await context());

  /// Positional arguments.
  List<String> get rest => argResults!.rest;

  /// Throws a usage error if more than [max] positional arguments were given.
  void maxArgs(int max) {
    if (rest.length > max) usageException('Too many arguments.');
  }
}
