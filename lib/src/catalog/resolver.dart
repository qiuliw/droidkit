import 'package:droidkit/src/catalog/models.dart';
import 'package:droidkit/src/host/host_platform.dart';

/// Newest command-line tools that Flutter's license check understands.
///
/// cmdline-tools 23 deprecated `sdkmanager --licenses`, so Flutter <= 3.47
/// reports "Android license status unknown"
/// (https://github.com/flutter/flutter/issues/191487). Bump this once Flutter
/// handles the new Android CLI.
const flutterCompatibleCmdlineTools = '22.0';

/// System image tags, in order of preference, with a short description.
const systemImageTags = <String, String>{
  'google_apis_playstore':
      'Google Play Store + Google APIs (like a real phone)',
  'google_apis': 'Google APIs, rootable (no Play Store)',
  'default': 'Plain AOSP',
  'google_atd': 'Automated Test Device, headless & fast (for CI)',
  'aosp_atd': 'AOSP Automated Test Device (for CI)',
};

/// Picks concrete package versions out of a catalog.
class PackageResolver {
  /// Creates a [PackageResolver].
  const PackageResolver(this.catalog, this.host);

  /// The catalog to choose from.
  final SdkCatalog catalog;

  /// The host packages must run on.
  final HostPlatform host;

  static final _plainPlatform = RegExp(r'^platforms;android-(\d+)(?:\.0)?$');

  /// The stable API levels with a platform package, newest first.
  List<int> stablePlatformApis() {
    final apis = <int>{};
    for (final pkg in catalog.packages) {
      final m = _plainPlatform.firstMatch(pkg.path);
      if (m != null && !pkg.obsolete && pkg.channel == 0) {
        apis.add(int.parse(m.group(1)!));
      }
    }
    return apis.toList()..sort((a, b) => b.compareTo(a));
  }

  /// The sdkmanager path of the platform for [api], e.g. `platforms;android-36`.
  ///
  /// Handles Google's newer `android-37.0` style names.
  String? platformPath(int api) {
    for (final candidate in [
      'platforms;android-$api',
      'platforms;android-$api.0',
    ]) {
      if (catalog.find(candidate) != null) return candidate;
    }
    return null;
  }

  /// Newest stable build-tools, e.g. `build-tools;37.0.0`.
  RemotePackage? latestBuildTools() {
    RemotePackage? best;
    for (final pkg in catalog.packages) {
      if (!pkg.path.startsWith('build-tools;') ||
          pkg.isPreview ||
          pkg.obsolete ||
          pkg.archiveFor(host) == null) {
        continue;
      }
      if (best == null || pkg.revision > best.revision) best = pkg;
    }
    return best;
  }

  /// The command-line tools package and its archive for this host.
  ///
  /// [version] is `latest` or a version such as `22.0`.
  (RemotePackage, SdkArchive)? cmdlineTools({
    String version = flutterCompatibleCmdlineTools,
  }) {
    final pkg = catalog.find('cmdline-tools;$version');
    final archive = pkg?.archiveFor(host);
    if (pkg == null || archive == null) return null;
    return (pkg, archive);
  }

  /// Stable system images for this host's ABI, newest API first.
  ///
  /// Extension-level, 16 KB page size, preview and canary images are skipped
  /// unless [includePreview] is set.
  List<RemotePackage> systemImages({
    String? tag,
    int? api,
    bool includePreview = false,
  }) {
    final images = catalog.packages.where((pkg) {
      if (!pkg.path.startsWith('system-images;')) return false;
      if (pkg.abi != host.arch.systemImageAbi) return false;
      if (tag != null && pkg.tag != tag) return false;
      if (api != null && apiOf(pkg) != api) return false;
      if (pkg.obsolete || pkg.archiveFor(host) == null) return false;
      if (!includePreview &&
          (pkg.isPreview || (pkg.tag?.contains('ps16k') ?? false))) {
        return false;
      }
      return true;
    }).toList();
    images.sort((a, b) {
      final byApi = (apiOf(b) ?? 0).compareTo(apiOf(a) ?? 0);
      return byApi != 0 ? byApi : b.revision.compareTo(a.revision);
    });
    // Keep only the newest revision of each path.
    final seen = <String>{};
    return images.where((i) => seen.add(i.path)).toList();
  }

  /// Integer API level of a platform or system image package, if it has one.
  static int? apiOf(RemotePackage pkg) {
    final segment = pkg.path.split(';').elementAtOrNull(1) ?? '';
    final m = RegExp(r'^android-(\d+)(?:\.0)?$').firstMatch(segment);
    return m == null ? null : int.parse(m.group(1)!);
  }

  /// Best system image for [api] and [tag], or null.
  RemotePackage? systemImage({required int api, required String tag}) =>
      systemImages(tag: tag, api: api).firstOrNull;
}
