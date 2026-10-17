import 'package:droidkit/src/catalog/catalog_parser.dart';
import 'package:droidkit/src/catalog/models.dart';
import 'package:droidkit/src/catalog/resolver.dart';
import 'package:droidkit/src/host/host_platform.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import 'helpers/helpers.dart';

void main() {
  final base = Uri.parse('https://dl.google.com/android/repository/');
  late SdkCatalog main;
  late SdkCatalog images;

  setUpAll(() {
    main = CatalogParser.parse(fixture('repository2-3.xml'), base);
    images = CatalogParser.parse(
      fixture('sys-img-playstore.xml'),
      base.resolve('sys-img/google_apis_playstore/sys-img2-3.xml'),
    );
  });

  group('CatalogParser', () {
    test('reads licenses', () {
      expect(main.licenses.keys, contains('android-sdk-license'));
      expect(
        main.licenses['android-sdk-license']!.text,
        startsWith('Terms and Conditions'),
      );
    });

    test('maps channels and keeps every channel', () {
      final emulators = main.packages.where((p) => p.path == 'emulator');
      expect(emulators.map((e) => e.channel).toSet(), {0, 1, 2});
      expect(main.find('emulator')!.channel, 0);
      expect(
        main.find('emulator', maxChannel: 2)!.revision,
        greaterThan(main.find('emulator')!.revision),
      );
    });

    test('resolves archive URLs and host filters', () {
      final tools = main.find('cmdline-tools;latest')!;
      expect(tools.revision.major, 23);
      final linux = tools.archiveFor(fakeHost())!;
      expect(
        linux.url.toString(),
        'https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip',
      );
      expect(linux.sha1, hasLength(40));
      expect(linux.size, greaterThan(100000000));
      final macArm = tools.archiveFor(
        fakeHost(os: HostOs.macos, arch: HostArch.arm64),
      )!;
      expect(macArm.url.path, endsWith('mac_arm64-16111833_latest.zip'));
      final macIntel = tools.archiveFor(fakeHost(os: HostOs.macos))!;
      expect(macIntel.url.path, endsWith('mac_x86_64-16111833_latest.zip'));
    });

    test('marks preview revisions', () {
      final rc = main.packages.firstWhere(
        (p) => p.path == 'build-tools;37.0.0-rc2',
      );
      expect(rc.revision.isPreRelease, isTrue);
      expect(rc.isPreview, isTrue);
      expect(main.find('build-tools;37.0.0')!.isPreview, isFalse);
    });

    test('system image details come from the path', () {
      final ps16k = images.packages.firstWhere(
        (p) =>
            p.path.contains('google_apis_playstore_ps16k;x86_64') &&
            p.path.contains('android-36;'),
      );
      // The XML lists page_size_16kb first; the path is authoritative.
      expect(ps16k.tag, 'google_apis_playstore_ps16k');
      expect(ps16k.abi, 'x86_64');
      expect(ps16k.apiLevel, '36');
      expect(
        ps16k.archives.single.url.toString(),
        contains('/sys-img/google_apis_playstore/'),
      );
    });

    test('parses the addons list', () {
      const xml = '''
<common:site-list xmlns:common="x"><site><url>sys-img/google_apis/sys-img2-3.xml</url></site>
<site><url>addon2-3.xml</url></site></common:site-list>''';
      expect(CatalogParser.parseAddonsList(xml, base).map((u) => u.toString()), [
        'https://dl.google.com/android/repository/sys-img/google_apis/sys-img2-3.xml',
      ]);
    });
  });

  group('PackageResolver', () {
    final linux = fakeHost();
    final macArm = fakeHost(os: HostOs.macos, arch: HostArch.arm64);

    test('latest stable build-tools skips release candidates', () {
      expect(
        PackageResolver(main, linux).latestBuildTools()!.path,
        'build-tools;37.0.0',
      );
    });

    test('stable platforms include android-NN.0 and skip previews', () {
      final apis = PackageResolver(main, linux).stablePlatformApis();
      expect(apis.first, 37);
      expect(apis, containsAll([36, 35]));
      final resolver = PackageResolver(main, linux);
      expect(resolver.platformPath(37), 'platforms;android-37.0');
      expect(resolver.platformPath(36), 'platforms;android-36');
      expect(resolver.platformPath(99), isNull);
    });

    test('cmdline-tools default to the Flutter-compatible version', () {
      final (pkg, archive) = PackageResolver(main, linux).cmdlineTools()!;
      expect(pkg.path, 'cmdline-tools;$flutterCompatibleCmdlineTools');
      expect(archive.url.path, contains('linux'));
      final (latest, _) = PackageResolver(
        main,
        linux,
      ).cmdlineTools(version: 'latest')!;
      expect(latest.revision.major, 23);
    });

    test('system images match the host ABI and skip special variants', () {
      final x64 = PackageResolver(images, linux).systemImages();
      expect(x64.map((i) => i.path), [
        'system-images;android-36;google_apis_playstore;x86_64',
        'system-images;android-35;google_apis_playstore;x86_64',
      ]);
      final arm = PackageResolver(images, macArm).systemImages();
      expect(arm.single.abi, 'arm64-v8a');
    });

    test('includePreview returns extension and 16 KB images too', () {
      final all = PackageResolver(
        images,
        linux,
      ).systemImages(includePreview: true);
      expect(all.length, greaterThan(2));
    });

    test('systemImage picks by api and tag', () {
      final resolver = PackageResolver(images, linux);
      expect(
        resolver.systemImage(api: 35, tag: 'google_apis_playstore')!.path,
        'system-images;android-35;google_apis_playstore;x86_64',
      );
      expect(resolver.systemImage(api: 35, tag: 'google_apis'), isNull);
    });

    test('apiOf handles plain and .0 names only', () {
      int? api(String path) => PackageResolver.apiOf(
        RemotePackage(
          path: path,
          revision: Version.none,
          displayName: path,
          channel: 0,
          archives: const [],
        ),
      );
      expect(api('platforms;android-36'), 36);
      expect(api('platforms;android-37.0'), 37);
      expect(api('platforms;android-36-ext19'), isNull);
      expect(api('platforms;android-CANARY'), isNull);
    });
  });
}
