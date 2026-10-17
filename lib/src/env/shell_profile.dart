import 'package:droidkit/src/host/host_platform.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;

/// Shells droidkit can print environment setup for.
enum Shell {
  /// bash.
  bash,

  /// zsh.
  zsh,

  /// fish.
  fish,

  /// PowerShell (Windows PowerShell or pwsh).
  powershell,

  /// Windows cmd.exe.
  cmd;

  /// Guesses the user's shell from the environment.
  static Shell detect(HostPlatform host) {
    final shell = p.basename(host.environment['SHELL'] ?? '');
    if (shell.contains('zsh')) return Shell.zsh;
    if (shell.contains('fish')) return Shell.fish;
    if (shell.contains('bash')) return Shell.bash;
    if (host.isWindows) {
      // PSModulePath is set inside PowerShell sessions only.
      return host.environment.containsKey('PSModulePath') &&
              !host.environment.containsKey('PROMPT')
          ? Shell.powershell
          : Shell.cmd;
    }
    return host.isMacOS ? Shell.zsh : Shell.bash;
  }
}

/// The environment droidkit wants in every shell.
class ToolchainEnvironment {
  /// Creates a [ToolchainEnvironment].
  const ToolchainEnvironment({required this.sdkRoot, this.javaHome});

  /// ANDROID_HOME.
  final String sdkRoot;

  /// JAVA_HOME, if droidkit knows a JDK.
  final String? javaHome;

  /// Directories to prepend to PATH, relative to their variable.
  List<(String, String)> get pathEntries => [
    ('ANDROID_HOME', 'cmdline-tools/latest/bin'),
    ('ANDROID_HOME', 'platform-tools'),
    ('ANDROID_HOME', 'emulator'),
    if (javaHome != null) ('JAVA_HOME', 'bin'),
  ];

  /// Absolute PATH entries (for Windows user PATH).
  List<String> absolutePathEntries() => [
    for (final (variable, sub) in pathEntries)
      p.windows.joinAll([
        if (variable == 'ANDROID_HOME') sdkRoot else javaHome!,
        ...sub.split('/'),
      ]),
  ];

  static String _quote(String value) =>
      '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll(r'$', r'\$').replaceAll('`', r'\`')}"';

  static String _psQuote(String value) => "'${value.replaceAll("'", "''")}'";

  /// Shell code that sets up the environment.
  String render(Shell shell) {
    final lines = <String>[];
    switch (shell) {
      case Shell.bash:
      case Shell.zsh:
        lines.add('export ANDROID_HOME=${_quote(sdkRoot)}');
        if (javaHome != null) {
          lines.add('export JAVA_HOME=${_quote(javaHome!)}');
        }
        final path = pathEntries.map((e) => '\$${e.$1}/${e.$2}').join(':');
        lines.add('export PATH="$path:\$PATH"');
      case Shell.fish:
        lines.add('set -gx ANDROID_HOME ${_quote(sdkRoot)}');
        if (javaHome != null) {
          lines.add('set -gx JAVA_HOME ${_quote(javaHome!)}');
        }
        final path = pathEntries.map((e) => '"\$${e.$1}/${e.$2}"').join(' ');
        lines.add('fish_add_path -g --move $path');
      case Shell.powershell:
        lines.add('\$env:ANDROID_HOME = ${_psQuote(sdkRoot)}');
        if (javaHome != null) {
          lines.add('\$env:JAVA_HOME = ${_psQuote(javaHome!)}');
        }
        final path = absolutePathEntries().join(';');
        lines.add('\$env:Path = ${_psQuote('$path;')} + \$env:Path');
      case Shell.cmd:
        lines.add('set "ANDROID_HOME=$sdkRoot"');
        if (javaHome != null) lines.add('set "JAVA_HOME=$javaHome"');
        lines.add('set "PATH=${absolutePathEntries().join(';')};%PATH%"');
    }
    return lines.join('\n');
  }
}

/// Start/end markers of the block droidkit manages in shell rc files.
const blockStart = '# >>> droidkit >>>';

/// End marker, see [blockStart].
const blockEnd = '# <<< droidkit <<<';

/// Writes and removes droidkit's block in shell startup files.
class ShellProfile {
  /// Creates a [ShellProfile].
  const ShellProfile(this.host, this.fs);

  /// Host platform.
  final HostPlatform host;

  /// File system.
  final FileSystem fs;

  /// The startup file droidkit edits for [shell].
  String rcFile(Shell shell) {
    final home = host.homeDirectory;
    switch (shell) {
      case Shell.zsh:
        final zdot = host.environment['ZDOTDIR'];
        return p.join(zdot != null && zdot.isNotEmpty ? zdot : home, '.zshrc');
      case Shell.bash:
        // macOS Terminal opens login shells, which read .bash_profile.
        if (host.isMacOS) return p.join(home, '.bash_profile');
        return p.join(home, '.bashrc');
      case Shell.fish:
        final config = host.environment['XDG_CONFIG_HOME'];
        return p.join(
          config != null && config.isNotEmpty
              ? config
              : p.join(home, '.config'),
          'fish',
          'conf.d',
          'droidkit.fish',
        );
      case Shell.powershell:
      case Shell.cmd:
        throw UnsupportedError('Windows uses user environment variables');
    }
  }

  /// Inserts or replaces droidkit's block in [shell]'s rc file.
  /// Returns the file path.
  String persist(Shell shell, ToolchainEnvironment env) {
    final path = rcFile(shell);
    final file = fs.file(path);
    final body =
        '$blockStart\n'
        '# Added by droidkit (https://pub.dev/packages/droidkit).\n'
        '# Remove with: droidkit env --unpersist\n'
        '${env.render(shell)}\n'
        '$blockEnd\n';
    final existing = file.existsSync() ? file.readAsStringSync() : '';
    final stripped = removeBlock(existing);
    final separator = stripped.isEmpty || stripped.endsWith('\n\n')
        ? ''
        : stripped.endsWith('\n')
        ? '\n'
        : '\n\n';
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('$stripped$separator$body');
    return path;
  }

  /// Removes droidkit's block from [shell]'s rc file. Returns whether a block
  /// was found.
  bool unpersist(Shell shell) {
    final file = fs.file(rcFile(shell));
    if (!file.existsSync()) return false;
    final content = file.readAsStringSync();
    final stripped = removeBlock(content);
    if (stripped == content) return false;
    if (shell == Shell.fish && stripped.trim().isEmpty) {
      file.deleteSync();
    } else {
      file.writeAsStringSync(stripped);
    }
    return true;
  }

  /// [content] without droidkit's block (and the blank line before it).
  static String removeBlock(String content) {
    final start = content.indexOf(blockStart);
    if (start < 0) return content;
    final endMarker = content.indexOf(blockEnd, start);
    if (endMarker < 0) return content;
    var end = endMarker + blockEnd.length;
    if (end < content.length && content[end] == '\n') end++;
    var before = content.substring(0, start);
    if (before.endsWith('\n\n')) {
      before = before.substring(0, before.length - 1);
    }
    return before + content.substring(end);
  }

  /// PowerShell script that persists [env] as user environment variables.
  static String windowsPersistScript(ToolchainEnvironment env) {
    String q(String s) => "'${s.replaceAll("'", "''")}'";
    final entries = env.absolutePathEntries().map(q).join(',');
    return [
      "[Environment]::SetEnvironmentVariable('ANDROID_HOME', ${q(env.sdkRoot)}, 'User')",
      if (env.javaHome != null)
        "[Environment]::SetEnvironmentVariable('JAVA_HOME', ${q(env.javaHome!)}, 'User')",
      r"$current = [Environment]::GetEnvironmentVariable('Path', 'User')",
      r'if ($null -eq $current) { $current = "" }',
      r"$parts = @($current -split ';' | Where-Object { $_ -ne '' })",
      '\$add = @($entries) | Where-Object { \$parts -notcontains \$_ }',
      r"$new = (@($add) + $parts) -join ';'",
      r"[Environment]::SetEnvironmentVariable('Path', $new, 'User')",
    ].join('; ');
  }

  /// PowerShell script that removes what [windowsPersistScript] added.
  static String windowsUnpersistScript(ToolchainEnvironment env) {
    String q(String s) => "'${s.replaceAll("'", "''")}'";
    final entries = env.absolutePathEntries().map(q).join(',');
    return [
      "[Environment]::SetEnvironmentVariable('ANDROID_HOME', \$null, 'User')",
      if (env.javaHome != null)
        "[Environment]::SetEnvironmentVariable('JAVA_HOME', \$null, 'User')",
      r"$current = [Environment]::GetEnvironmentVariable('Path', 'User')",
      r'if ($null -eq $current) { $current = "" }',
      '\$remove = @($entries)',
      r"$new = (@($current -split ';') | Where-Object { $_ -ne '' -and $remove -notcontains $_ }) -join ';'",
      r"[Environment]::SetEnvironmentVariable('Path', $new, 'User')",
    ].join('; ');
  }
}
