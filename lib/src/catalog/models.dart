import 'package:droidkit/src/host/host_platform.dart';
import 'package:pub_semver/pub_semver.dart';

/// A license from the SDK repository.
class SdkLicense {
  /// Creates an [SdkLicense].
  const SdkLicense(this.id, this.text);

  /// License id, e.g. `android-sdk-license`.
  final String id;

  /// Full license text.
  final String text;
}

/// One downloadable file of a [RemotePackage].
class SdkArchive {
  /// Creates an [SdkArchive].
  const SdkArchive({
    required this.url,
    required this.sha1,
    required this.size,
    this.hostOs,
    this.hostArch,
  });

  /// Absolute download URL.
  final Uri url;

  /// Expected SHA-1 of the file.
  final String sha1;

  /// Size in bytes.
  final int size;

  /// `linux`, `macosx`, `windows`, or null for any host.
  final String? hostOs;

  /// `x64`, `aarch64`, or null for any architecture.
  final String? hostArch;

  /// Whether this archive can be installed on [host].
  bool matches(HostPlatform host) =>
      (hostOs == null || hostOs == host.os.catalogName) &&
      (hostArch == null || hostArch == host.arch.catalogName);
}

/// A package listed in an SDK repository catalog.
class RemotePackage {
  /// Creates a [RemotePackage].
  const RemotePackage({
    required this.path,
    required this.revision,
    required this.displayName,
    required this.channel,
    required this.archives,
    this.licenseRef,
    this.obsolete = false,
    this.apiLevel,
    this.extensionLevel,
    this.tag,
    this.abi,
  });

  /// sdkmanager path, e.g. `platforms;android-36`.
  final String path;

  /// Package revision (`-rc.N` pre-release when it is a preview).
  final Version revision;

  /// Human readable name.
  final String displayName;

  /// 0 = stable, 1 = beta, 2 = dev, 3 = canary.
  final int channel;

  /// Downloadable archives.
  final List<SdkArchive> archives;

  /// Id of the license the user must accept.
  final String? licenseRef;

  /// Whether Google marked this package obsolete.
  final bool obsolete;

  /// API level (platforms and system images).
  final String? apiLevel;

  /// SDK extension level (system images).
  final int? extensionLevel;

  /// System image tag, e.g. `google_apis_playstore`.
  final String? tag;

  /// System image ABI, e.g. `x86_64`.
  final String? abi;

  /// Total download size for [host], or null when unavailable there.
  int? sizeFor(HostPlatform host) => archiveFor(host)?.size;

  /// The archive for [host], or null when unavailable there.
  SdkArchive? archiveFor(HostPlatform host) {
    for (final archive in archives) {
      if (archive.matches(host)) return archive;
    }
    return null;
  }

  /// Whether this is a preview (rc/beta/canary/extension) rather than a plain
  /// stable release.
  bool get isPreview {
    if (channel != 0 || revision.isPreRelease) return true;
    final last = path.split(';').elementAtOrNull(1) ?? '';
    return RegExp(r'(-ext\d+|-beta|canary|CANARY|-rc)').hasMatch(last) ||
        path.contains('-rc');
  }
}

/// A parsed SDK repository catalog (possibly merged from several XML files).
class SdkCatalog {
  /// Creates an [SdkCatalog].
  const SdkCatalog({required this.packages, required this.licenses});

  /// All packages, across every channel.
  final List<RemotePackage> packages;

  /// Licenses by id.
  final Map<String, SdkLicense> licenses;

  /// Merges [other] into a new catalog.
  SdkCatalog merge(SdkCatalog other) => SdkCatalog(
    packages: [...packages, ...other.packages],
    licenses: {...licenses, ...other.licenses},
  );

  /// Newest package with [path] on [maxChannel] or a more stable channel.
  RemotePackage? find(String path, {int maxChannel = 0}) {
    RemotePackage? best;
    for (final pkg in packages) {
      if (pkg.path != path || pkg.channel > maxChannel) continue;
      if (best == null || pkg.revision > best.revision) best = pkg;
    }
    return best;
  }
}
