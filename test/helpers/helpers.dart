import 'dart:io';

import 'package:droidkit/src/host/host_platform.dart';

/// A fake host for tests.
HostPlatform fakeHost({
  HostOs os = HostOs.linux,
  HostArch arch = HostArch.x64,
  Map<String, String>? environment,
  bool isWsl = false,
}) => HostPlatform(
  os: os,
  arch: arch,
  environment: environment ?? {'HOME': '/home/dev'},
  isWsl: isWsl,
);

/// The contents of `test/fixtures/<name>`.
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// Creates a temp directory deleted after the test.
Directory tempDir(void Function(void Function()) addTearDown) {
  final dir = Directory.systemTemp.createTempSync('droidkit_test_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}
