import 'package:droidkit/src/host/host_platform.dart';
import 'package:test/test.dart';

import 'helpers/helpers.dart';

void main() {
  test('parseArch understands uname and Windows names', () {
    expect(HostPlatform.parseArch('x86_64\n'), HostArch.x64);
    expect(HostPlatform.parseArch('AMD64'), HostArch.x64);
    expect(HostPlatform.parseArch('aarch64'), HostArch.arm64);
    expect(HostPlatform.parseArch('ARM64'), HostArch.arm64);
    expect(HostPlatform.parseArch('i686'), HostArch.other);
    expect(HostPlatform.parseArch('riscv64'), HostArch.other);
  });

  group('emulator support matrix', () {
    final cases = {
      (HostOs.linux, HostArch.x64): true,
      (HostOs.linux, HostArch.arm64): false,
      (HostOs.macos, HostArch.x64): true,
      (HostOs.macos, HostArch.arm64): true,
      (HostOs.windows, HostArch.x64): true,
      (HostOs.windows, HostArch.arm64): false,
      (HostOs.linux, HostArch.other): false,
    };
    cases.forEach((key, supported) {
      test('${key.$1.name}-${key.$2.name}', () {
        final host = fakeHost(os: key.$1, arch: key.$2);
        expect(host.supportsEmulator, supported);
        expect(host.emulatorUnsupportedReason == null, supported);
      });
    });
    test('no platform-tools on linux arm64', () {
      expect(fakeHost(arch: HostArch.arm64).supportsPlatformTools, isFalse);
      expect(
        fakeHost(os: HostOs.macos, arch: HostArch.arm64).supportsPlatformTools,
        isTrue,
      );
    });
  });

  test('default SDK roots follow Android Studio conventions', () {
    expect(fakeHost().defaultSdkRoot, '/home/dev/Android/Sdk');
    expect(
      fakeHost(
        os: HostOs.macos,
        environment: {'HOME': '/Users/me'},
      ).defaultSdkRoot,
      '/Users/me/Library/Android/sdk',
    );
    expect(
      fakeHost(
        os: HostOs.windows,
        environment: {
          'USERPROFILE': r'C:\Users\me',
          'LOCALAPPDATA': r'C:\Users\me\AppData\Local',
        },
      ).defaultSdkRoot,
      r'C:\Users\me\AppData\Local\Android\Sdk',
    );
  });

  test('ABI and suffixes', () {
    expect(fakeHost().arch.systemImageAbi, 'x86_64');
    expect(fakeHost(arch: HostArch.arm64).arch.systemImageAbi, 'arm64-v8a');
    expect(fakeHost(os: HostOs.windows).scriptSuffix, '.bat');
    expect(fakeHost(os: HostOs.windows).exeSuffix, '.exe');
    expect(fakeHost().scriptSuffix, '');
  });

  test('CI detection', () {
    expect(fakeHost(environment: {'CI': 'true'}).isCi, isTrue);
    expect(fakeHost(environment: {'GITHUB_ACTIONS': 'true'}).isCi, isTrue);
    expect(fakeHost().isCi, isFalse);
  });

  test('description mentions WSL', () {
    expect(fakeHost(isWsl: true).description, 'linux-x64 (WSL)');
    expect(
      fakeHost(os: HostOs.macos, arch: HostArch.arm64).description,
      'macos-arm64',
    );
  });
}
