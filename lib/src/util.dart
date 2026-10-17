import 'dart:io';

import 'package:droidkit/src/host/host_platform.dart';
import 'package:droidkit/src/process/process_runner.dart';

/// Formats a byte count, e.g. `1.8 GB`.
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0
      ? '$bytes B'
      : '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[unit]}';
}

/// Free disk space (bytes) on the volume holding [path], or null if unknown.
///
/// [path] need not exist yet; its nearest existing ancestor is used.
Future<int?> freeBytes(
  String path,
  HostPlatform host,
  ProcessRunner runner,
) async {
  var dir = Directory(path).absolute;
  while (!dir.existsSync() && dir.parent.path != dir.path) {
    dir = dir.parent;
  }
  if (host.isWindows) {
    final drive = dir.path.length >= 2 ? dir.path.substring(0, 1) : 'C';
    final r = await runner.run('powershell', [
      '-NoProfile',
      '-Command',
      '(Get-PSDrive $drive).Free',
    ]);
    return int.tryParse(r.stdout.trim());
  }
  final r = await runner.run('df', ['-Pk', dir.path]);
  if (!r.ok) return null;
  final lines = r.stdout.trim().split('\n');
  if (lines.length < 2) return null;
  final cols = lines.last.split(RegExp(r'\s+'));
  if (cols.length < 4) return null;
  final kb = int.tryParse(cols[3]);
  return kb == null ? null : kb * 1024;
}

/// Makes [name] a valid AVD name (letters, digits, `.`, `_`, `-`).
String sanitizeAvdName(String name) {
  final cleaned = name
      .trim()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');
  return cleaned.isEmpty ? 'droidkit_avd' : cleaned;
}

/// Whether the current user can write inside [path] (or create it).
bool isWritable(String path) {
  var dir = Directory(path);
  while (!dir.existsSync() && dir.parent.path != dir.path) {
    dir = dir.parent;
  }
  try {
    final probe = File(
      '${dir.path}${Platform.pathSeparator}.droidkit_write_test_$pid',
    )..writeAsStringSync('');
    probe.deleteSync();
    return true;
  } on FileSystemException {
    return false;
  }
}
