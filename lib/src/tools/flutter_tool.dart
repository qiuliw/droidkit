import 'dart:io';

import 'package:droidkit/src/process/process_runner.dart';
import 'package:path/path.dart' as p;

/// Talks to the `flutter` CLI, if it is installed.
class FlutterTool {
  /// Creates a [FlutterTool].
  FlutterTool(this.runner);

  /// Process runner.
  final ProcessRunner runner;

  String? _executable;
  bool _looked = false;
  Map<String, String>? _config;

  /// Path of `flutter`, or null when Flutter is not on PATH.
  Future<String?> executable() async {
    if (!_looked) {
      _looked = true;
      _executable = await runner.which('flutter');
    }
    return _executable;
  }

  /// Parses `flutter config --list` output into a map.
  static Map<String, String> parseConfigList(String output) {
    final result = <String, String>{};
    for (final line in output.split('\n')) {
      final m = RegExp(
        r'^\s+([\w-]+):\s+(.+?)\s*(\(Unavailable\))?$',
      ).firstMatch(line);
      if (m != null) result[m.group(1)!] = m.group(2)!;
    }
    return result;
  }

  /// Flutter's global settings (`android-sdk`, `jdk-dir`, …).
  Future<Map<String, String>> config() async {
    if (_config != null) return _config!;
    final flutter = await executable();
    if (flutter == null) return _config = {};
    final r = await runner.run(flutter, [
      'config',
      '--list',
    ], timeout: const Duration(minutes: 2));
    return _config = r.ok ? parseConfigList(r.stdout) : {};
  }

  /// Points Flutter at [sdkRoot] and/or [jdkHome]. Returns false if Flutter
  /// is missing or the command failed.
  Future<bool> configure({String? sdkRoot, String? jdkHome}) async {
    final flutter = await executable();
    if (flutter == null || (sdkRoot == null && jdkHome == null)) return false;
    final r = await runner.run(flutter, [
      'config',
      if (sdkRoot != null) ...['--android-sdk', sdkRoot],
      if (jdkHome != null) ...['--jdk-dir', jdkHome],
    ], timeout: const Duration(minutes: 2));
    _config = null;
    return r.ok;
  }

  /// Reads the default `compileSdk` of the installed Flutter SDK, so droidkit
  /// installs the platform Flutter will actually build against.
  Future<int?> defaultCompileSdk(String Function(String path) readFile) async {
    final value = await _readGradleDefault(
      RegExp(r'compileSdkVersion\s*(?::\s*Int)?\s*=\s*(\d+)'),
      readFile,
    );
    return value == null ? null : int.parse(value);
  }

  /// Reads the default `ndkVersion` of the installed Flutter SDK.
  Future<String?> defaultNdkVersion(String Function(String path) readFile) =>
      _readGradleDefault(
        RegExp(r'ndkVersion\s*(?::\s*String)?\s*=\s*"([\d.]+)"'),
        readFile,
      );

  Future<String?> _readGradleDefault(
    RegExp pattern,
    String Function(String path) readFile,
  ) async {
    final flutter = await executable();
    if (flutter == null) return null;
    // <flutter>/bin/flutter -> <flutter>/packages/flutter_tools/...
    var resolved = flutter;
    try {
      resolved = File(flutter).resolveSymbolicLinksSync();
    } on FileSystemException {
      // Use as-is.
    }
    final root = p.dirname(p.dirname(resolved));
    for (final candidate in [
      p.join(
        root,
        'packages',
        'flutter_tools',
        'gradle',
        'src',
        'main',
        'kotlin',
        'FlutterExtension.kt',
      ),
      p.join(
        root,
        'packages',
        'flutter_tools',
        'gradle',
        'src',
        'main',
        'groovy',
        'flutter.groovy',
      ),
    ]) {
      try {
        final m = pattern.firstMatch(readFile(candidate));
        if (m != null) return m.group(1);
      } on Object {
        continue;
      }
    }
    return null;
  }
}
