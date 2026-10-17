import 'package:droidkit/src/avd/avd_service.dart';
import 'package:droidkit/src/process/process_runner.dart';
import 'package:droidkit/src/tools/android_tools.dart';
import 'package:droidkit/src/tools/flutter_tool.dart';
import 'package:droidkit/src/util.dart';
import 'package:test/test.dart';

void main() {
  test('avdmanager list device', () {
    const output = '''
Available devices definitions:
id: 0 or "automotive_1024p_landscape"
    Name: Automotive (1024p landscape)
    OEM : Google
    Tag : android-automotive-playstore
---------
id: 5 or "Galaxy Nexus"
    Name: Galaxy Nexus
    OEM : Google
---------
id: 30 or "pixel_8"
    Name: Pixel 8
    OEM : Google
---------
''';
    final devices = AndroidTools.parseDevices(output);
    expect(devices.map((d) => d.id), [
      'automotive_1024p_landscape',
      'Galaxy Nexus',
      'pixel_8',
    ]);
    expect(devices.first.tag, 'android-automotive-playstore');
    expect(devices.last.name, 'Pixel 8');
    expect(devices.last.tag, isNull);
    expect(AvdService.defaultDevice(devices), 'pixel_8');
    expect(AvdService.defaultDevice([]), isNull);
  });

  test('flutter config --list', () {
    const output = '''
All Settings:
  enable-web: (Not set)
  android-sdk: /home/dev/Android
  jdk-dir: /usr/lib/jvm/java-17-openjdk/
  enable-android: true (Unavailable)
''';
    final config = FlutterTool.parseConfigList(output);
    expect(config['android-sdk'], '/home/dev/Android');
    expect(config['jdk-dir'], '/usr/lib/jvm/java-17-openjdk/');
    expect(config['enable-web'], '(Not set)');
    expect(config['enable-android'], 'true');
  });

  test('ini parsing and updating', () {
    const ini =
        'hw.keyboard=no\n# comment=x\nimage.sysdir.1=system-images/android-36/google_apis/x86_64/\n\n';
    final values = parseIni(ini);
    expect(values['hw.keyboard'], 'no');
    expect(values.containsKey('# comment'), isFalse);
    final updated = updateIni(ini, {
      'hw.keyboard': 'yes',
      'hw.gpu.mode': 'auto',
    });
    expect(parseIni(updated)['hw.keyboard'], 'yes');
    expect(parseIni(updated)['hw.gpu.mode'], 'auto');
    expect(updated, contains('# comment=x'));
    expect(updated, endsWith('hw.gpu.mode=auto\n'));
  });

  test('formatBytes', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(181052239), '173 MB');
    expect(formatBytes(1924689206), '1.8 GB');
  });

  test('sanitizeAvdName', () {
    expect(sanitizeAvdName('Pixel 8_API_36'), 'Pixel_8_API_36');
    expect(sanitizeAvdName('my/phone*'), 'myphone');
    expect(sanitizeAvdName('  '), 'droidkit_avd');
  });

  test('cmd-safe arguments for .bat files', () {
    // The scripts forward %*, so ; and = pass through as-is; adding quotes
    // would reach sdkmanager as \" once Dart escapes them for cmd.
    expect(
      ProcessRunner.cmdSafeArguments(['--install', 'platforms;android-36']),
      ['--install', 'platforms;android-36'],
    );
    expect(ProcessRunner.cmdSafeArguments([r'--sdk_root=C:\Sdk']), [
      r'--sdk_root=C:\Sdk',
    ]);
    // Dart already quotes arguments with spaces; leave them alone.
    expect(
      ProcessRunner.cmdSafeArguments([r'--sdk_root=C:\Users\Jo & Doe\Sdk']),
      [r'--sdk_root=C:\Users\Jo & Doe\Sdk'],
    );
    expect(ProcessRunner.cmdSafeArguments([r'C:\R&D\Sdk']), [r'C:\R^&D\Sdk']);
  });
}
