import 'dart:io';

import 'package:droidkit/src/catalog/catalog_parser.dart';
import 'package:droidkit/src/catalog/models.dart';
import 'package:droidkit/src/net/downloader.dart';
import 'package:path/path.dart' as p;

/// Fetches Google's SDK catalogs, caching them on disk.
///
/// Catalogs are refreshed after [maxAge]. If the network is unavailable a
/// stale cache is used, so read-only commands keep working offline.
class CatalogRepository {
  /// Creates a [CatalogRepository].
  CatalogRepository({
    required this.downloader,
    required this.cacheDir,
    this.maxAge = const Duration(hours: 12),
    Uri? baseUrl,
  }) : baseUrl =
           baseUrl ??
           Uri.parse(
             Platform.environment['DROIDKIT_REPOSITORY_URL'] ??
                 'https://dl.google.com/android/repository/',
           );

  /// Network access.
  final Downloader downloader;

  /// Where catalogs are cached.
  final String cacheDir;

  /// How long a cached catalog stays fresh.
  final Duration maxAge;

  /// Root of Google's repository.
  final Uri baseUrl;

  SdkCatalog? _main;
  SdkCatalog? _images;

  /// The main SDK catalog (cmdline-tools, platforms, build-tools, emulator…).
  Future<SdkCatalog> main({bool refresh = false}) async {
    if (_main != null && !refresh) return _main!;
    final url = baseUrl.resolve('repository2-3.xml');
    return _main = CatalogParser.parse(
      await _fetch(url, 'repository2-3.xml', refresh: refresh),
      url,
    );
  }

  /// All system images, merged from every sys-img catalog.
  ///
  /// When [tags] is given only those catalogs are fetched (much faster).
  Future<SdkCatalog> systemImages({
    Set<String>? tags,
    bool refresh = false,
  }) async {
    if (_images != null && !refresh && tags == null) return _images!;
    final addonsUrl = baseUrl.resolve('addons_list-5.xml');
    var urls = CatalogParser.parseAddonsList(
      await _fetch(addonsUrl, 'addons_list-5.xml', refresh: refresh),
      addonsUrl,
    );
    if (tags != null) {
      urls = urls
          .where((u) => tags.contains(u.pathSegments.reversed.elementAt(1)))
          .toList();
    }
    var catalog = const SdkCatalog(packages: [], licenses: {});
    final parsed = await Future.wait([
      for (final url in urls)
        _fetch(
          url,
          'sys-img-${url.pathSegments.reversed.elementAt(1)}.xml',
          refresh: refresh,
        ).then((xml) => CatalogParser.parse(xml, url)),
    ]);
    for (final c in parsed) {
      catalog = catalog.merge(c);
    }
    if (tags == null) _images = catalog;
    return catalog;
  }

  Future<String> _fetch(Uri url, String name, {required bool refresh}) async {
    final cached = File(p.join(cacheDir, name));
    final fresh =
        cached.existsSync() &&
        DateTime.now().difference(cached.lastModifiedSync()) < maxAge;
    if (fresh && !refresh) return cached.readAsString();
    try {
      final body = await downloader.getString(url);
      await cached.parent.create(recursive: true);
      await cached.writeAsString(body);
      return body;
    } on DownloadException {
      if (cached.existsSync()) return cached.readAsString();
      rethrow;
    }
  }
}
