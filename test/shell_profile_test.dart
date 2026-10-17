import 'dart:io';

import 'package:droidkit/src/env/shell_profile.dart';
import 'package:droidkit/src/host/host_platform.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/helpers.dart';

void main() {
  const env = ToolchainEnvironment(
    sdkRoot: '/home/dev/Android/Sdk',
    javaHome: '/home/dev/.droidkit/jdk/temurin-21',
  );

  group('render', () {
    test('bash/zsh', () {
      final out = env.render(Shell.bash);
      expect(out, contains('export ANDROID_HOME="/home/dev/Android/Sdk"'));
      expect(
        out,
        contains('export JAVA_HOME="/home/dev/.droidkit/jdk/temurin-21"'),
      );
      expect(
        out,
        contains(
          r'export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:'
          r'$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:'
          r'$JAVA_HOME/bin:$PATH"',
        ),
      );
    });

    test('quotes special characters for POSIX shells', () {
      const tricky = ToolchainEnvironment(sdkRoot: r'/tmp/a "b" $c');
      expect(
        tricky.render(Shell.zsh),
        contains(r'export ANDROID_HOME="/tmp/a \"b\" \$c"'),
      );
    });

    test('fish', () {
      final out = env.render(Shell.fish);
      expect(out, contains('set -gx ANDROID_HOME "/home/dev/Android/Sdk"'));
      expect(out, contains('fish_add_path -g --move'));
    });

    test('powershell and cmd use absolute Windows paths', () {
      const win = ToolchainEnvironment(sdkRoot: r'C:\Android\Sdk');
      expect(
        win.render(Shell.powershell),
        contains(r"$env:ANDROID_HOME = 'C:\Android\Sdk'"),
      );
      expect(
        win.render(Shell.powershell),
        contains(r'C:\Android\Sdk\cmdline-tools\latest\bin;'),
      );
      expect(
        win.render(Shell.cmd),
        contains(r'set "ANDROID_HOME=C:\Android\Sdk"'),
      );
      expect(win.render(Shell.cmd), endsWith(';%PATH%"'));
    });

    test('omits JAVA_HOME when unknown', () {
      const noJava = ToolchainEnvironment(sdkRoot: '/sdk');
      expect(noJava.render(Shell.bash), isNot(contains('JAVA_HOME')));
    });
  });

  group('Shell.detect', () {
    test('from SHELL', () {
      expect(
        Shell.detect(fakeHost(environment: {'SHELL': '/bin/zsh'})),
        Shell.zsh,
      );
      expect(
        Shell.detect(fakeHost(environment: {'SHELL': '/usr/bin/fish'})),
        Shell.fish,
      );
      expect(
        Shell.detect(fakeHost(environment: {'SHELL': '/bin/bash'})),
        Shell.bash,
      );
    });
    test('platform defaults', () {
      expect(Shell.detect(fakeHost(environment: {})), Shell.bash);
      expect(
        Shell.detect(fakeHost(os: HostOs.macos, environment: {})),
        Shell.zsh,
      );
    });
  });

  group('ShellProfile', () {
    late Directory home;
    late ShellProfile profile;

    setUp(() {
      home = tempDir(addTearDown);
      profile = ShellProfile(
        fakeHost(environment: {'HOME': home.path}),
        const LocalFileSystem(),
      );
    });

    test('persist keeps existing content and is idempotent', () {
      final rc = File(p.join(home.path, '.bashrc'))
        ..writeAsStringSync('alias ll="ls -l"\n');
      profile
        ..persist(Shell.bash, env)
        ..persist(Shell.bash, env);
      final content = rc.readAsStringSync();
      expect(content, startsWith('alias ll="ls -l"\n'));
      expect(blockStart.allMatches(content), hasLength(1));
      expect(content, contains('export ANDROID_HOME='));
    });

    test('persist replaces an outdated block', () {
      profile.persist(Shell.zsh, env);
      profile.persist(Shell.zsh, const ToolchainEnvironment(sdkRoot: '/new'));
      final content = File(p.join(home.path, '.zshrc')).readAsStringSync();
      expect(content, contains('/new'));
      expect(content, isNot(contains('/home/dev/Android/Sdk')));
    });

    test('unpersist restores the original file', () {
      const original = 'export FOO=1\n\nexport BAR=2\n';
      final rc = File(p.join(home.path, '.bashrc'))
        ..writeAsStringSync(original);
      profile.persist(Shell.bash, env);
      expect(profile.unpersist(Shell.bash), isTrue);
      expect(rc.readAsStringSync(), original);
      expect(profile.unpersist(Shell.bash), isFalse);
    });

    test('fish gets its own conf.d file, removed on unpersist', () {
      final path = profile.persist(Shell.fish, env);
      expect(path, endsWith(p.join('fish', 'conf.d', 'droidkit.fish')));
      expect(File(path).existsSync(), isTrue);
      profile.unpersist(Shell.fish);
      expect(File(path).existsSync(), isFalse);
    });

    test('respects ZDOTDIR', () {
      final zdot = p.join(home.path, 'zsh');
      final custom = ShellProfile(
        fakeHost(environment: {'HOME': home.path, 'ZDOTDIR': zdot}),
        const LocalFileSystem(),
      );
      expect(custom.rcFile(Shell.zsh), p.join(zdot, '.zshrc'));
    });

    test('macOS bash uses .bash_profile', () {
      final mac = ShellProfile(
        fakeHost(os: HostOs.macos, environment: {'HOME': home.path}),
        const LocalFileSystem(),
      );
      expect(mac.rcFile(Shell.bash), p.join(home.path, '.bash_profile'));
    });
  });

  test('Windows scripts touch only droidkit entries', () {
    const win = ToolchainEnvironment(sdkRoot: r"C:\Users\O'Neil\Sdk");
    final persist = ShellProfile.windowsPersistScript(win);
    expect(persist, contains("'C:\\Users\\O''Neil\\Sdk'"));
    expect(persist, contains("SetEnvironmentVariable('Path'"));
    expect(persist, isNot(contains('JAVA_HOME')));
    final unpersist = ShellProfile.windowsUnpersistScript(win);
    expect(
      unpersist,
      contains(r"SetEnvironmentVariable('ANDROID_HOME', $null"),
    );
  });
}
