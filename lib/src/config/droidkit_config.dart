import 'dart:convert';

import 'package:file/file.dart';
import 'package:path/path.dart' as p;

/// Locations of droidkit's own state (`~/.droidkit` unless `DROIDKIT_HOME`
/// is set).
class DroidkitPaths {
  /// Creates [DroidkitPaths] rooted at [root].
  const DroidkitPaths(this.root);

  /// Resolves the root from the environment.
  factory DroidkitPaths.fromEnvironment(
    Map<String, String> env,
    String homeDirectory,
  ) {
    final override = env['DROIDKIT_HOME'];
    return DroidkitPaths(
      override != null && override.isNotEmpty
          ? override
          : p.join(homeDirectory, '.droidkit'),
    );
  }

  /// Root directory.
  final String root;

  /// `config.json`.
  String get configFile => p.join(root, 'config.json');

  /// Cached repository catalogs.
  String get cacheDir => p.join(root, 'cache');

  /// In-progress downloads and extractions.
  String get tmpDir => p.join(root, 'tmp');

  /// Emulator logs.
  String get logDir => p.join(root, 'logs');

  /// JDKs installed by droidkit.
  String get jdkDir => p.join(root, 'jdk');
}

/// Persistent droidkit settings.
class DroidkitConfig {
  /// Creates a [DroidkitConfig].
  DroidkitConfig({
    this.sdkRoot,
    this.managedSdk = false,
    this.jdkHome,
    this.defaultAvd,
  });

  /// Reads the config file, returning defaults if it is missing or corrupt.
  factory DroidkitConfig.load(FileSystem fs, DroidkitPaths paths) {
    final file = fs.file(paths.configFile);
    if (!file.existsSync()) return DroidkitConfig();
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return DroidkitConfig(
        sdkRoot: json['sdkRoot'] as String?,
        managedSdk: json['managedSdk'] as bool? ?? false,
        jdkHome: json['jdkHome'] as String?,
        defaultAvd: json['defaultAvd'] as String?,
      );
    } on Object {
      return DroidkitConfig();
    }
  }

  /// Android SDK root chosen or created by droidkit.
  String? sdkRoot;

  /// Whether droidkit created [sdkRoot] (and may therefore delete it).
  bool managedSdk;

  /// JDK home chosen or installed by droidkit.
  String? jdkHome;

  /// AVD started by `droidkit start` when no name is given.
  String? defaultAvd;

  /// Writes the config file.
  void save(FileSystem fs, DroidkitPaths paths) {
    final file = fs.file(paths.configFile);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'sdkRoot': ?sdkRoot,
        'managedSdk': managedSdk,
        'jdkHome': ?jdkHome,
        'defaultAvd': ?defaultAvd,
      }),
    );
  }
}
