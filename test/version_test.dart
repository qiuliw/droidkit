import 'dart:io';

import 'package:droidkit/src/version.dart';
import 'package:test/test.dart';

void main() {
  test('packageVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(packageVersion, version);
  });

  test('CHANGELOG has an entry for the current version', () {
    final changelog = File('CHANGELOG.md').readAsStringSync();
    expect(changelog, contains('## $packageVersion'));
  });
}
