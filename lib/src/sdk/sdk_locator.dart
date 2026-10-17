import 'package:droidkit/src/host/host_platform.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;

/// A candidate Android SDK location and where droidkit learned about it.
class SdkLocation {
  /// Creates an [SdkLocation].
  const SdkLocation(this.root, this.source);

  /// SDK root directory.
  final String root;

  /// E.g. `ANDROID_HOME`, `--sdk-root`, `default location`.
  final String source;
}

/// Decides which Android SDK directory droidkit works with.
class SdkLocator {
  /// Creates an [SdkLocator].
  const SdkLocator(this.host, this.fs);

  /// Host platform.
  final HostPlatform host;

  /// File system.
  final FileSystem fs;

  /// Whether [root] looks like an Android SDK (not just an empty folder).
  bool looksLikeSdk(String root) => [
    'cmdline-tools',
    'platform-tools',
    'platforms',
    'build-tools',
    'tools',
    'emulator',
  ].any((d) => fs.directory(p.join(root, d)).existsSync());

  /// Candidate SDK locations in priority order.
  List<SdkLocation> candidates({
    String? override,
    String? configured,
    String? flutterConfigured,
  }) {
    final env = host.environment;
    return [
      if (override != null) SdkLocation(override, '--sdk-root'),
      if (configured != null) SdkLocation(configured, 'droidkit config'),
      if (env['ANDROID_HOME'] case final v? when v.isNotEmpty)
        SdkLocation(v, 'ANDROID_HOME'),
      if (env['ANDROID_SDK_ROOT'] case final v? when v.isNotEmpty)
        SdkLocation(v, 'ANDROID_SDK_ROOT'),
      if (flutterConfigured != null)
        SdkLocation(flutterConfigured, 'flutter config --android-sdk'),
      SdkLocation(host.defaultSdkRoot, 'default location'),
    ];
  }

  /// Picks the SDK to use.
  ///
  /// An explicit `--sdk-root` always wins, even if it doesn't exist yet (so
  /// `setup` can create it). Otherwise the first candidate that looks like a
  /// real SDK is used, falling back to the OS default location.
  SdkLocation choose(List<SdkLocation> candidates) {
    final explicit = candidates.where((c) => c.source == '--sdk-root');
    if (explicit.isNotEmpty) return explicit.first;
    for (final c in candidates) {
      if (looksLikeSdk(c.root)) return c;
    }
    return candidates.last;
  }
}
