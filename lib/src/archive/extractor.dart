import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// Extracts downloaded archives (zip, tar.gz).
class Extractor {
  /// Creates an [Extractor].
  const Extractor();

  /// Extracts [archivePath] into a fresh [destination] directory.
  ///
  /// If the archive contains a single top-level directory (as almost every
  /// SDK/JDK archive does), its contents are placed directly in
  /// [destination]. Extraction happens in a sibling temp directory and is
  /// moved into place at the end, so a failed extraction never leaves a
  /// half-populated [destination].
  Future<void> extract(String archivePath, String destination) async {
    final staging = Directory('$destination.extracting');
    if (staging.existsSync()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    try {
      await extractFileToDisk(archivePath, staging.path);
      var source = staging;
      final entries = staging.listSync();
      // package:archive silently extracts nothing from a corrupt file; never
      // let that replace a working installation with an empty directory.
      if (entries.isEmpty) {
        throw FormatException(
          '${describe(archivePath)} is empty or not a valid archive',
        );
      }
      if (entries.length == 1 && entries.single is Directory) {
        source = entries.single as Directory;
      }
      final dest = Directory(destination);
      if (dest.existsSync()) await dest.delete(recursive: true);
      await dest.parent.create(recursive: true);
      await source.rename(dest.path);
    } finally {
      if (staging.existsSync()) await staging.delete(recursive: true);
    }
  }

  /// Human readable name of [archivePath] for messages.
  static String describe(String archivePath) => p.basename(archivePath);
}
