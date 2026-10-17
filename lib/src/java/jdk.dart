import 'package:droidkit/src/host/host_platform.dart';
import 'package:droidkit/src/process/process_runner.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;

/// Oldest JDK the Android command-line tools run on.
const minJavaVersion = 17;

/// Newest JDK Flutter's Gradle tooling is known to support.
const maxJavaVersion = 25;

/// JDK major version droidkit installs when none is found.
const defaultJavaVersion = 21;

/// A JDK found on this machine.
class Jdk {
  /// Creates a [Jdk].
  const Jdk({
    required this.home,
    required this.majorVersion,
    required this.versionString,
    required this.source,
    required this.hasJavac,
  });

  /// JAVA_HOME for this JDK.
  final String home;

  /// Major version (e.g. 21).
  final int majorVersion;

  /// Full version string from `java -version`.
  final String versionString;

  /// Where it was found, e.g. `JAVA_HOME` or `droidkit`.
  final String source;

  /// Whether `javac` is present (a JRE is not enough for Gradle).
  final bool hasJavac;

  /// Whether this JDK is usable for Android + Flutter builds.
  bool get isSupported =>
      hasJavac &&
      majorVersion >= minJavaVersion &&
      majorVersion <= maxJavaVersion;

  /// Why the JDK is not usable, or null.
  String? get problem {
    if (!hasJavac) return 'is a JRE (no javac); Gradle needs a full JDK';
    if (majorVersion < minJavaVersion) {
      return 'is Java $majorVersion; the Android tools need $minJavaVersion+';
    }
    if (majorVersion > maxJavaVersion) {
      return 'is Java $majorVersion; Flutter/Gradle support up to '
          '$maxJavaVersion';
    }
    return null;
  }
}

/// Finds and inspects JDKs.
class JdkLocator {
  /// Creates a [JdkLocator].
  const JdkLocator({
    required this.host,
    required this.fs,
    required this.runner,
    required this.droidkitJdkDir,
  });

  /// Host platform.
  final HostPlatform host;

  /// File system.
  final FileSystem fs;

  /// Process runner.
  final ProcessRunner runner;

  /// Where droidkit installs its own JDKs.
  final String droidkitJdkDir;

  /// Parses the major version out of `java -version` output.
  static (int, String)? parseVersion(String output) {
    final m = RegExp(r'version "([^"]+)"').firstMatch(output);
    if (m == null) return null;
    final full = m.group(1)!;
    final parts = full.split(RegExp('[._+-]'));
    var major = int.tryParse(parts.first) ?? 0;
    // Java 8 and earlier report "1.8.0_x".
    if (major == 1 && parts.length > 1) major = int.tryParse(parts[1]) ?? 0;
    return (major, full);
  }

  /// Inspects the JDK at [home], or returns null if it isn't one.
  Future<Jdk?> inspect(String home, String source) async {
    final java = p.join(home, 'bin', 'java${host.exeSuffix}');
    if (!fs.file(java).existsSync()) return null;
    final result = await runner.run(java, ['-version']);
    final parsed = parseVersion('${result.stderr}\n${result.stdout}');
    if (parsed == null) return null;
    return Jdk(
      home: home,
      majorVersion: parsed.$1,
      versionString: parsed.$2,
      source: source,
      hasJavac: fs
          .file(p.join(home, 'bin', 'javac${host.exeSuffix}'))
          .existsSync(),
    );
  }

  /// Every JDK droidkit can find, in priority order (duplicates removed).
  ///
  /// [configured] is droidkit's saved JDK; [flutterJdkDir] is Flutter's
  /// `jdk-dir` setting.
  Future<List<Jdk>> findAll({String? configured, String? flutterJdkDir}) async {
    final candidates = <(String, String)>[
      if (configured != null) (configured, 'droidkit config'),
      if (flutterJdkDir != null) (flutterJdkDir, 'flutter config --jdk-dir'),
      if (host.environment['JAVA_HOME'] case final javaHome?)
        (javaHome, 'JAVA_HOME'),
      ...installedByDroidkit().map((h) => (h, 'droidkit')),
      ...await _fromPath(),
      ...androidStudioJbrs().map((h) => (h, 'Android Studio')),
    ];
    final seen = <String>{};
    final jdks = <Jdk>[];
    for (final (home, source) in candidates) {
      final normalized = _normalize(home);
      if (!seen.add(normalized)) continue;
      final jdk = await inspect(home, source);
      if (jdk != null) jdks.add(jdk);
    }
    return jdks;
  }

  /// The best usable JDK, or null.
  Future<Jdk?> findBest({String? configured, String? flutterJdkDir}) async {
    final all = await findAll(
      configured: configured,
      flutterJdkDir: flutterJdkDir,
    );
    return all.where((j) => j.isSupported).firstOrNull;
  }

  /// JDK homes under droidkit's own directory, newest first.
  List<String> installedByDroidkit() {
    final dir = fs.directory(droidkitJdkDir);
    if (!dir.existsSync()) return [];
    final homes = <String>[];
    for (final d in dir.listSync().whereType<Directory>()) {
      if (d.basename.endsWith('.extracting')) continue;
      homes.add(javaHomeIn(d.path));
    }
    homes.sort((a, b) => b.compareTo(a));
    return homes;
  }

  /// macOS JDK archives nest the real home in `Contents/Home`.
  String javaHomeIn(String extracted) {
    final mac = p.join(extracted, 'Contents', 'Home');
    return fs.directory(mac).existsSync() ? mac : extracted;
  }

  /// Android Studio's bundled JetBrains Runtime, if Android Studio exists.
  List<String> androidStudioJbrs() {
    final home = host.homeDirectory;
    return switch (host.os) {
      HostOs.macos => [
        '/Applications/Android Studio.app/Contents/jbr/Contents/Home',
        '$home/Applications/Android Studio.app/Contents/jbr/Contents/Home',
      ],
      HostOs.windows => [
        r'C:\Program Files\Android\Android Studio\jbr',
        '${host.environment['LOCALAPPDATA'] ?? ''}\\Programs\\Android Studio\\jbr',
      ],
      HostOs.linux => [
        '/opt/android-studio/jbr',
        '$home/android-studio/jbr',
        '/usr/local/android-studio/jbr',
        '/snap/android-studio/current/jbr',
      ],
    }.where((d) => fs.directory(d).existsSync()).toList();
  }

  Future<List<(String, String)>> _fromPath() async {
    final java = await runner.which('java');
    if (java == null) return [];
    // Resolve symlinks like /usr/bin/java -> /usr/lib/jvm/.../bin/java.
    var resolved = java;
    try {
      resolved = fs.file(java).resolveSymbolicLinksSync();
    } on FileSystemException {
      // Keep the unresolved path.
    }
    final home = p.dirname(p.dirname(resolved));
    // macOS /usr/bin/java is a stub; ask java_home for the real one.
    if (host.isMacOS && home == '/usr') {
      final r = await runner.run('/usr/libexec/java_home', []);
      return r.ok ? [(r.stdout.trim(), 'PATH')] : [];
    }
    return [(home, 'PATH')];
  }

  String _normalize(String path) {
    var normalized = p.normalize(path);
    try {
      normalized = fs.directory(path).resolveSymbolicLinksSync();
    } on FileSystemException {
      // Doesn't exist; keep as-is.
    }
    return host.isWindows ? normalized.toLowerCase() : normalized;
  }
}
