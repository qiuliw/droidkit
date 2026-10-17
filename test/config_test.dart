import 'dart:io';

import 'package:droidkit/src/config/droidkit_config.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/helpers.dart';

void main() {
  test('DROIDKIT_HOME overrides the default location', () {
    expect(
      DroidkitPaths.fromEnvironment({
        'DROIDKIT_HOME': '/custom',
      }, '/home/dev').root,
      '/custom',
    );
    expect(
      DroidkitPaths.fromEnvironment({}, '/home/dev').root,
      p.join('/home/dev', '.droidkit'),
    );
  });

  test('round-trips and tolerates corruption', () {
    final paths = DroidkitPaths(tempDir(addTearDown).path);
    const fs = LocalFileSystem();
    expect(DroidkitConfig.load(fs, paths).sdkRoot, isNull);

    DroidkitConfig(
      sdkRoot: '/sdk',
      managedSdk: true,
      jdkHome: '/jdk',
      defaultAvd: 'Pixel',
    ).save(fs, paths);
    final loaded = DroidkitConfig.load(fs, paths);
    expect(loaded.sdkRoot, '/sdk');
    expect(loaded.managedSdk, isTrue);
    expect(loaded.jdkHome, '/jdk');
    expect(loaded.defaultAvd, 'Pixel');

    File(paths.configFile).writeAsStringSync('{not json');
    expect(DroidkitConfig.load(fs, paths).sdkRoot, isNull);
  });
}
