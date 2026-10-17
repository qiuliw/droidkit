import 'package:droidkit/src/host/host_platform.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// A package installed in the local SDK (read from its `package.xml`).
class InstalledPackage {
  /// Creates an [InstalledPackage].
  const InstalledPackage(this.path, this.version, this.directory);

  /// sdkmanager path, e.g. `platforms;android-36`.
  final String path;

  /// Installed revision, e.g. `36.0.0`.
  final String version;

  /// Directory it lives in.
  final String directory;
}

/// An Android SDK directory on disk and the tools inside it.
class AndroidSdk {
  /// Creates an [AndroidSdk] rooted at [root].
  const AndroidSdk(this.root, this.host, this.fs);

  /// SDK root (what `ANDROID_HOME` points to).
  final String root;

  /// Host platform (decides `.bat`/`.exe` suffixes).
  final HostPlatform host;

  /// File system.
  final FileSystem fs;

  /// Whether [root] exists.
  bool get exists => fs.directory(root).existsSync();

  /// `cmdline-tools/latest/bin`.
  String get cmdlineToolsBin => p.join(root, 'cmdline-tools', 'latest', 'bin');

  /// Path to `sdkmanager`.
  String get sdkmanager =>
      p.join(cmdlineToolsBin, 'sdkmanager${host.scriptSuffix}');

  /// Path to `avdmanager`.
  String get avdmanager =>
      p.join(cmdlineToolsBin, 'avdmanager${host.scriptSuffix}');

  /// Path to `emulator`.
  String get emulator => p.join(root, 'emulator', 'emulator${host.exeSuffix}');

  /// Path to `adb`.
  String get adb => p.join(root, 'platform-tools', 'adb${host.exeSuffix}');

  /// Whether `cmdline-tools/latest` is installed.
  bool get hasCmdlineTools => fs.file(sdkmanager).existsSync();

  /// Whether the emulator is installed.
  bool get hasEmulator => fs.file(emulator).existsSync();

  /// Whether platform-tools (adb) is installed.
  bool get hasPlatformTools => fs.file(adb).existsSync();

  /// cmdline-tools installed in a non-standard place (`tools/bin`, or
  /// `cmdline-tools/<version>/bin` without `latest`). Flutter and droidkit
  /// both expect `cmdline-tools/latest`.
  String? get misplacedCmdlineTools {
    if (hasCmdlineTools) return null;
    final name = 'sdkmanager${host.scriptSuffix}';
    final cmdline = fs.directory(p.join(root, 'cmdline-tools'));
    if (cmdline.existsSync()) {
      for (final dir in cmdline.listSync().whereType<Directory>()) {
        if (fs.file(p.join(dir.path, 'bin', name)).existsSync()) {
          return dir.path;
        }
      }
      // Unzipped straight into cmdline-tools/ (bin/ at the top level).
      if (fs.file(p.join(cmdline.path, 'bin', name)).existsSync()) {
        return cmdline.path;
      }
    }
    final legacy = p.join(root, 'tools', 'bin', name);
    if (fs.file(legacy).existsSync()) return p.join(root, 'tools');
    return null;
  }

  /// Version of the cmdline-tools in `cmdline-tools/latest` (from its
  /// `source.properties`), e.g. `22.0`.
  String? get cmdlineToolsVersion {
    final props = fs.file(
      p.join(root, 'cmdline-tools', 'latest', 'source.properties'),
    );
    if (!props.existsSync()) return null;
    final m = RegExp(
      r'^Pkg\.Revision\s*=\s*(\S+)',
      multiLine: true,
    ).firstMatch(props.readAsStringSync());
    return m?.group(1);
  }

  /// Major version of [cmdlineToolsVersion].
  int? get cmdlineToolsMajor =>
      int.tryParse(cmdlineToolsVersion?.split('.').first ?? '');

  /// License ids that have an acceptance file in `licenses/`.
  Set<String> acceptedLicenseFiles() {
    final dir = fs.directory(p.join(root, 'licenses'));
    if (!dir.existsSync()) return {};
    return {
      for (final f in dir.listSync().whereType<File>()) p.basename(f.path),
    };
  }

  /// All installed packages, found by scanning for `package.xml` files.
  ///
  /// This is much faster than `sdkmanager --list_installed` (no JVM start).
  List<InstalledPackage> installedPackages() {
    final result = <InstalledPackage>[];
    final rootDir = fs.directory(root);
    if (!rootDir.existsSync()) return result;

    void scan(Directory dir, int depth) {
      final xml = fs.file(p.join(dir.path, 'package.xml'));
      if (xml.existsSync()) {
        final pkg = _parsePackageXml(xml);
        if (pkg != null) result.add(pkg);
        return;
      }
      if (depth >= 4) return;
      List<FileSystemEntity> children;
      try {
        children = dir.listSync(followLinks: false);
      } on FileSystemException {
        return;
      }
      for (final child in children.whereType<Directory>()) {
        final name = p.basename(child.path);
        // Skip huge directories that never contain nested packages.
        if (depth > 0 && (name == 'lib' || name == 'lib64' || name == 'bin')) {
          continue;
        }
        scan(child, depth + 1);
      }
    }

    scan(rootDir, 0);
    result.sort((a, b) => a.path.compareTo(b.path));
    return result;
  }

  /// Whether a package with [path] is installed.
  bool isInstalled(String path) =>
      installedPackages().any((pkg) => pkg.path == path);

  /// The directory an sdkmanager [path] installs into.
  String directoryFor(String path) => p.joinAll([root, ...path.split(';')]);

  InstalledPackage? _parsePackageXml(File file) {
    try {
      final doc = XmlDocument.parse(file.readAsStringSync());
      final local = doc.findAllElements('localPackage').firstOrNull;
      final path = local?.getAttribute('path');
      if (local == null || path == null) return null;
      final rev = local.findElements('revision').firstOrNull;
      String part(String n) => rev?.getElement(n)?.innerText.trim() ?? '';
      final version = [
        part('major'),
        part('minor'),
        part('micro'),
      ].where((s) => s.isNotEmpty).join('.');
      final preview = part('preview');
      return InstalledPackage(
        path,
        preview.isEmpty ? version : '$version-rc$preview',
        file.parent.path,
      );
    } on Object {
      return null;
    }
  }
}
