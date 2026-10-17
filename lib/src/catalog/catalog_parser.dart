import 'package:droidkit/src/catalog/models.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:xml/xml.dart';

/// Parses Google's `repository2-3.xml` / `sys-img2-3.xml` catalogs.
class CatalogParser {
  const CatalogParser._();

  /// Parses [xml]; relative archive URLs are resolved against [baseUrl].
  static SdkCatalog parse(String xml, Uri baseUrl) {
    final doc = XmlDocument.parse(xml);
    final root = doc.rootElement;

    final licenses = <String, SdkLicense>{};
    for (final el in root.childElements.where(
      (e) => e.localName == 'license',
    )) {
      final id = el.getAttribute('id');
      if (id != null) licenses[id] = SdkLicense(id, el.innerText);
    }

    final channels = <String, int>{};
    for (final el in root.childElements.where(
      (e) => e.localName == 'channel',
    )) {
      final id = el.getAttribute('id');
      final n = int.tryParse(id?.split('-').last ?? '');
      if (id != null && n != null) channels[id] = n;
    }

    final packages = <RemotePackage>[];
    for (final el in root.childElements.where(
      (e) => e.localName == 'remotePackage',
    )) {
      final path = el.getAttribute('path');
      if (path == null) continue;
      final details = _child(el, 'type-details');
      // Images can carry several <tag>s (e.g. page_size_16kb +
      // google_apis_playstore); the path segment is the canonical id.
      final segments = path.split(';');
      final tag = segments.first == 'system-images' && segments.length == 4
          ? segments[2]
          : details == null
          ? null
          : _text(_child(details, 'tag') ?? details, 'id');
      packages.add(
        RemotePackage(
          path: path,
          revision: _revision(_child(el, 'revision')),
          displayName: _text(el, 'display-name') ?? path,
          channel: channels[_child(el, 'channelRef')?.getAttribute('ref')] ?? 0,
          licenseRef: _child(el, 'uses-license')?.getAttribute('ref'),
          obsolete:
              el.getAttribute('obsolete') == 'true' ||
              _text(el, 'obsolete') == 'true',
          apiLevel: details == null ? null : _text(details, 'api-level'),
          extensionLevel: details == null
              ? null
              : int.tryParse(_text(details, 'extension-level') ?? ''),
          tag: tag,
          abi: details == null ? null : _text(details, 'abi'),
          archives: [
            for (final a
                in _child(
                      el,
                      'archives',
                    )?.childElements.where((e) => e.localName == 'archive') ??
                    const <XmlElement>[])
              if (_child(a, 'complete') case final complete?)
                SdkArchive(
                  url: baseUrl.resolve(_text(complete, 'url') ?? ''),
                  sha1: _text(complete, 'checksum') ?? '',
                  size: int.tryParse(_text(complete, 'size') ?? '') ?? 0,
                  hostOs: _text(a, 'host-os'),
                  hostArch: _text(a, 'host-arch'),
                ),
          ],
        ),
      );
    }
    return SdkCatalog(packages: packages, licenses: licenses);
  }

  /// Extracts the sys-img catalog URLs listed in `addons_list-5.xml`.
  static List<Uri> parseAddonsList(String xml, Uri baseUrl) {
    final doc = XmlDocument.parse(xml);
    return [
      for (final el in doc.findAllElements('url'))
        if (el.innerText.trim().startsWith('sys-img/'))
          baseUrl.resolve(el.innerText.trim()),
    ];
  }

  static XmlElement? _child(XmlElement el, String name) =>
      el.childElements.where((e) => e.localName == name).firstOrNull;

  static String? _text(XmlElement el, String name) =>
      _child(el, name)?.innerText.trim();

  static Version _revision(XmlElement? el) {
    if (el == null) return Version.none;
    int part(String name) => int.tryParse(_text(el, name) ?? '') ?? 0;
    final preview = _text(el, 'preview');
    return Version(
      part('major'),
      part('minor'),
      part('micro'),
      pre: preview == null ? null : 'rc.$preview',
    );
  }
}
