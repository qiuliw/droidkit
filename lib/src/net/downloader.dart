import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Thrown when a download fails permanently.
class DownloadException implements Exception {
  /// Creates a [DownloadException].
  DownloadException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => message;
}

/// Hash algorithm used to verify a download.
enum HashType {
  /// SHA-1 (used by Google's SDK repository).
  sha1,

  /// SHA-256 (used by Adoptium).
  sha256,
}

/// Called with bytes received so far and the total (or null if unknown).
typedef ProgressCallback = void Function(int received, int? total);

/// Small HTTP client that honours proxy environment variables, retries, and
/// verifies checksums. All network access goes through this class.
class Downloader {
  /// Creates a [Downloader].
  Downloader({
    HttpClient? client,
    this.maxAttempts = 3,
    this.retryDelay = const Duration(seconds: 2),
  }) : _client = client ?? _defaultClient();

  /// A client whose responses are never transparently decompressed.

  static HttpClient _defaultClient() {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..userAgent = 'droidkit (+https://pub.dev/packages/droidkit)';
    // HttpClient ignores HTTP(S)_PROXY unless told otherwise.
    client
      ..findProxy = HttpClient.findProxyFromEnvironment
      ..autoUncompress = false;
    return client;
  }

  final HttpClient _client;

  /// How many times to try each request.
  final int maxAttempts;

  /// Base delay between attempts (multiplied by the attempt number).
  final Duration retryDelay;

  /// Fetches [url] as a UTF-8 string.
  Future<String> getString(Uri url) => _retry(url, () async {
    final response = await _open(url);
    return response.transform(utf8.decoder).join();
  });

  /// Downloads [url] to [destination], verifying [expectedHash] if given.
  ///
  /// The file is written next to [destination] with a `.part` suffix and only
  /// renamed once complete and verified, so an interrupted download never
  /// leaves a corrupt file behind.
  Future<void> download(
    Uri url,
    String destination, {
    String? expectedHash,
    HashType hashType = HashType.sha1,
    ProgressCallback? onProgress,
  }) async {
    final part = File('$destination.part');
    await part.parent.create(recursive: true);
    await _retry(url, () async {
      final response = await _open(url);
      final encoded =
          response.headers.value(HttpHeaders.contentEncodingHeader) != null;
      final total = response.contentLength >= 0 && !encoded
          ? response.contentLength
          : null;
      final digestSink = _DigestSink();
      final hashSink = (hashType == HashType.sha1 ? sha1 : sha256)
          .startChunkedConversion(digestSink);
      final out = part.openWrite();
      var received = 0;
      var lastReport = DateTime.fromMillisecondsSinceEpoch(0);
      try {
        await for (final chunk in response) {
          out.add(chunk);
          hashSink.add(chunk);
          received += chunk.length;
          final now = DateTime.now();
          if (onProgress != null &&
              now.difference(lastReport) > const Duration(milliseconds: 150)) {
            lastReport = now;
            onProgress(received, total);
          }
        }
      } finally {
        await out.close();
      }
      hashSink.close();
      onProgress?.call(received, total);
      if (total != null && received != total) {
        throw const HttpException('Connection closed before download finished');
      }
      if (expectedHash != null && expectedHash.isNotEmpty) {
        final actual = digestSink.value.toString();
        if (actual.toLowerCase() != expectedHash.toLowerCase()) {
          await part.delete();
          throw _ChecksumMismatch(
            'Checksum mismatch for ${p.basename(url.path)}: '
            'expected $expectedHash, got $actual',
          );
        }
      }
    });
    final dest = File(destination);
    if (dest.existsSync()) await dest.delete();
    await part.rename(destination);
  }

  Future<HttpClientResponse> _open(Uri url) async {
    final request = await _client.getUrl(url);
    // Without this, servers may gzip the response; HttpClient then inflates it
    // and the byte count no longer matches Content-Length.
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw _HttpStatusError(response.statusCode, url);
    }
    return response;
  }

  Future<T> _retry<T>(Uri url, Future<T> Function() body) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await body();
      } on _HttpStatusError catch (e) {
        // 4xx will not fix itself.
        if (e.status >= 400 && e.status < 500) {
          throw DownloadException('HTTP ${e.status} for $url');
        }
        lastError = e;
      } on _ChecksumMismatch catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on HttpException catch (e) {
        lastError = e;
      } on HandshakeException catch (e) {
        lastError = e;
      } on TimeoutException catch (e) {
        lastError = e;
      }
      if (attempt < maxAttempts) {
        await Future<void>.delayed(retryDelay * attempt);
      }
    }
    throw DownloadException(
      'Could not download $url after $maxAttempts attempts: $lastError\n'
      'Check your internet connection. Behind a proxy? Set HTTPS_PROXY.',
    );
  }

  /// Releases network resources.
  void close() => _client.close(force: true);
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

class _HttpStatusError implements Exception {
  _HttpStatusError(this.status, this.url);
  final int status;
  final Uri url;

  @override
  String toString() => 'HTTP $status for $url';
}

class _ChecksumMismatch implements Exception {
  _ChecksumMismatch(this.message);
  final String message;

  @override
  String toString() => message;
}
