import 'dart:io';

import 'package:droidkit/src/host/host_platform.dart';
import 'package:droidkit/src/sdk/android_sdk.dart';
import 'package:droidkit/src/sdk/sdk_locator.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/helpers.dart';

const fs = LocalFileSystem();

void writePackage(String root, String path, String major, [String? minor]) {
  final dir = Directory(p.joinAll([root, ...path.split(';')]))
    ..createSync(recursive: true);
  File(p.join(dir.path, 'package.xml')).writeAsStringSync('''
<ns2:repository xmlns:ns2="http://schemas.android.com/repository/android/common/02">
  <localPackage path="$path" obsolete="false">
    <revision><major>$major</major>${minor == null ? '' : '<minor>$minor</minor>'}</revision>
  </localPackage>
</ns2:repository>''');
}

void main() {
  late String root;
  late AndroidSdk sdk;
  final host = fakeHost();

  setUp(() {
    root = tempDir(addTearDown).path;
    sdk = AndroidSdk(root, host, fs);
  });

  test('tool paths', () {
    expect(
      sdk.sdkmanager,
      p.join(root, 'cmdline-tools', 'latest', 'bin', 'sdkmanager'),
    );
    expect(sdk.emulator, p.join(root, 'emulator', 'emulator'));
    final win = AndroidSdk(root, fakeHost(os: HostOs.windows), fs);
    expect(win.sdkmanager, endsWith('sdkmanager.bat'));
    expect(win.adb, endsWith('adb.exe'));
  });

  test('installedPackages scans package.xml files', () {
    writePackage(root, 'platform-tools', '37', '0');
    writePackage(root, 'platforms;android-36', '2');
    writePackage(root, 'build-tools;37.0.0', '37', '0');
    writePackage(root, 'system-images;android-36;google_apis;x86_64', '7');
    final installed = sdk.installedPackages();
    expect(installed.map((i) => i.path), [
      'build-tools;37.0.0',
      'platform-tools',
      'platforms;android-36',
      'system-images;android-36;google_apis;x86_64',
    ]);
    expect(installed.first.version, '37.0');
    expect(sdk.isInstalled('platforms;android-36'), isTrue);
    expect(sdk.isInstalled('platforms;android-35'), isFalse);
  });

  test('cmdline-tools detection, version and misplaced copies', () {
    expect(sdk.hasCmdlineTools, isFalse);
    expect(sdk.misplacedCmdlineTools, isNull);

    final versioned = Directory(p.join(root, 'cmdline-tools', '19.0', 'bin'))
      ..createSync(recursive: true);
    File(p.join(versioned.path, 'sdkmanager')).writeAsStringSync('');
    expect(sdk.misplacedCmdlineTools, p.join(root, 'cmdline-tools', '19.0'));

    final latest = Directory(p.join(root, 'cmdline-tools', 'latest', 'bin'))
      ..createSync(recursive: true);
    File(p.join(latest.path, 'sdkmanager')).writeAsStringSync('');
    File(
      p.join(root, 'cmdline-tools', 'latest', 'source.properties'),
    ).writeAsStringSync(
      'Pkg.Desc=Android SDK Command-line Tools\nPkg.Revision=22.0\n',
    );
    expect(sdk.hasCmdlineTools, isTrue);
    expect(sdk.misplacedCmdlineTools, isNull);
    expect(sdk.cmdlineToolsVersion, '22.0');
    expect(sdk.cmdlineToolsMajor, 22);
  });

  test('legacy tools/ layout is reported', () {
    Directory(p.join(root, 'tools', 'bin')).createSync(recursive: true);
    File(p.join(root, 'tools', 'bin', 'sdkmanager')).writeAsStringSync('');
    expect(sdk.misplacedCmdlineTools, p.join(root, 'tools'));
  });

  test('accepted license files', () {
    Directory(p.join(root, 'licenses')).createSync();
    File(
      p.join(root, 'licenses', 'android-sdk-license'),
    ).writeAsStringSync('x');
    expect(sdk.acceptedLicenseFiles(), {'android-sdk-license'});
  });

  group('SdkLocator', () {
    test('priority order', () {
      final locator = SdkLocator(
        fakeHost(
          environment: {
            'HOME': '/home/dev',
            'ANDROID_HOME': '/env/home',
            'ANDROID_SDK_ROOT': '/env/root',
          },
        ),
        fs,
      );
      final candidates = locator.candidates(
        override: '/flag',
        configured: '/config',
        flutterConfigured: '/flutter',
      );
      expect(candidates.map((c) => c.source), [
        '--sdk-root',
        'droidkit config',
        'ANDROID_HOME',
        'ANDROID_SDK_ROOT',
        'flutter config --android-sdk',
        'default location',
      ]);
    });

    test('explicit --sdk-root wins even if missing', () {
      final locator = SdkLocator(host, fs);
      final chosen = locator.choose(locator.candidates(override: '/nope'));
      expect(chosen.root, '/nope');
    });

    test('first real SDK wins, otherwise the default', () {
      final locator = SdkLocator(
        fakeHost(
          environment: {'HOME': '/home/dev', 'ANDROID_HOME': '/missing'},
        ),
        fs,
      );
      Directory(p.join(root, 'platform-tools')).createSync();
      expect(
        locator.choose(locator.candidates(flutterConfigured: root)).root,
        root,
      );
      expect(locator.choose(locator.candidates()).source, 'default location');
    });
  });
}
