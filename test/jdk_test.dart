import 'package:droidkit/src/java/jdk.dart';
import 'package:test/test.dart';

void main() {
  group('JdkLocator.parseVersion', () {
    test('modern OpenJDK', () {
      expect(
        JdkLocator.parseVersion(
          'openjdk version "17.0.20.1" 2026-07-21\nOpenJDK Runtime Environment',
        ),
        (17, '17.0.20.1'),
      );
    });
    test('Java 8 style', () {
      expect(JdkLocator.parseVersion('java version "1.8.0_402"'), (
        8,
        '1.8.0_402',
      ));
    });
    test('early access and bare majors', () {
      expect(JdkLocator.parseVersion('openjdk version "26-ea" 2026'), (
        26,
        '26-ea',
      ));
      expect(JdkLocator.parseVersion('openjdk version "25" 2025-09-16'), (
        25,
        '25',
      ));
    });
    test('garbage', () {
      expect(JdkLocator.parseVersion('command not found'), isNull);
    });
  });

  group('Jdk.problem', () {
    Jdk jdk(int major, {bool javac = true}) => Jdk(
      home: '/jdk',
      majorVersion: major,
      versionString: '$major',
      source: 'test',
      hasJavac: javac,
    );

    test('supported range', () {
      expect(jdk(minJavaVersion).isSupported, isTrue);
      expect(jdk(maxJavaVersion).isSupported, isTrue);
      expect(jdk(defaultJavaVersion).problem, isNull);
    });
    test('too old / too new / JRE', () {
      expect(jdk(11).problem, contains('need 17+'));
      expect(jdk(maxJavaVersion + 1).problem, contains('up to'));
      expect(jdk(21, javac: false).problem, contains('JRE'));
    });
  });
}
