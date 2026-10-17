import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:droidkit/src/archive/extractor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/helpers.dart';

void main() {
  late Directory dir;

  setUp(() => dir = tempDir(addTearDown));

  String makeZip(Map<String, int> files) {
    final archive = Archive();
    for (final MapEntry(key: name, value: mode) in files.entries) {
      archive.add(
        ArchiveFile.bytes(name, 'content of $name'.codeUnits)..mode = mode,
      );
    }
    final path = p.join(dir.path, 'test.zip');
    File(path).writeAsBytesSync(ZipEncoder().encode(archive));
    return path;
  }

  test('strips a single top-level directory', () async {
    final zip = makeZip({
      'cmdline-tools/bin/sdkmanager': 0x1ed, // 0755
      'cmdline-tools/lib/tool.jar': 0x1a4, // 0644
    });
    final dest = p.join(dir.path, 'sdk', 'cmdline-tools', 'latest');
    await const Extractor().extract(zip, dest);
    final tool = File(p.join(dest, 'bin', 'sdkmanager'));
    expect(tool.existsSync(), isTrue);
    expect(File(p.join(dest, 'lib', 'tool.jar')).existsSync(), isTrue);
    expect(Directory('$dest.extracting').existsSync(), isFalse);
    if (!Platform.isWindows) {
      expect(tool.statSync().modeString(), startsWith('rwx'));
    }
  });

  test('keeps multiple top-level entries as they are', () async {
    final zip = makeZip({'a.txt': 0x1a4, 'b/c.txt': 0x1a4});
    final dest = p.join(dir.path, 'out');
    await const Extractor().extract(zip, dest);
    expect(File(p.join(dest, 'a.txt')).existsSync(), isTrue);
    expect(File(p.join(dest, 'b', 'c.txt')).existsSync(), isTrue);
  });

  test('replaces an existing destination', () async {
    final dest = p.join(dir.path, 'out');
    Directory(dest).createSync();
    File(p.join(dest, 'stale.txt')).writeAsStringSync('old');
    await const Extractor().extract(makeZip({'top/new.txt': 0x1a4}), dest);
    expect(File(p.join(dest, 'stale.txt')).existsSync(), isFalse);
    expect(File(p.join(dest, 'new.txt')).existsSync(), isTrue);
  });

  test('a corrupt archive leaves the destination untouched', () async {
    final dest = p.join(dir.path, 'out');
    Directory(dest).createSync();
    File(p.join(dest, 'keep.txt')).writeAsStringSync('keep');
    final bad = p.join(dir.path, 'bad.zip');
    File(bad).writeAsStringSync('not a zip');
    await expectLater(const Extractor().extract(bad, dest), throwsA(anything));
    expect(File(p.join(dest, 'keep.txt')).existsSync(), isTrue);
  });
}
