import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:droidkit/src/net/downloader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/helpers.dart';

void main() {
  late HttpServer server;
  late Uri base;
  final payload = List<int>.generate(300000, (i) => i % 251);
  var failuresLeft = 0;
  var requests = 0;

  setUp(() async {
    requests = 0;
    failuresLeft = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://${server.address.host}:${server.port}/');
    server.listen((request) async {
      requests++;
      final res = request.response;
      switch (request.uri.path) {
        case '/file':
          if (failuresLeft > 0) {
            failuresLeft--;
            res.statusCode = 503;
          } else {
            res.contentLength = payload.length;
            res.add(payload);
          }
        case '/gzip':
          // Mimics dl.google.com: gzip-encodes when the client allows it.
          final accepts =
              request.headers
                  .value(HttpHeaders.acceptEncodingHeader)
                  ?.contains('gzip') ??
              false;
          if (accepts) {
            final gz = gzip.encode(payload);
            res.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
            res.contentLength = gz.length;
            res.add(gz);
          } else {
            res.contentLength = payload.length;
            res.add(payload);
          }
        case '/text':
          res.write('hello');
        default:
          res.statusCode = 404;
      }
      await res.close();
    });
  });

  tearDown(() => server.close(force: true));

  Downloader downloader() =>
      Downloader(maxAttempts: 3, retryDelay: Duration.zero);

  test('downloads and verifies sha1', () async {
    final dest = p.join(tempDir(addTearDown).path, 'out.zip');
    await downloader().download(
      base.resolve('file'),
      dest,
      expectedHash: sha1.convert(payload).toString(),
    );
    expect(File(dest).readAsBytesSync(), payload);
    expect(File('$dest.part').existsSync(), isFalse);
  });

  test('verifies sha256 and reports progress', () async {
    final dest = p.join(tempDir(addTearDown).path, 'out.bin');
    int? lastReceived;
    await downloader().download(
      base.resolve('file'),
      dest,
      expectedHash: sha256.convert(payload).toString(),
      hashType: HashType.sha256,
      onProgress: (received, total) {
        lastReceived = received;
        expect(total, payload.length);
      },
    );
    expect(lastReceived, payload.length);
  });

  test('never receives gzip-mangled bytes', () async {
    final dest = p.join(tempDir(addTearDown).path, 'out.zip');
    await downloader().download(
      base.resolve('gzip'),
      dest,
      expectedHash: sha1.convert(payload).toString(),
    );
    expect(File(dest).readAsBytesSync(), payload);
  });

  test('checksum mismatch fails and leaves no file', () async {
    final dest = p.join(tempDir(addTearDown).path, 'out.zip');
    await expectLater(
      downloader().download(
        base.resolve('file'),
        dest,
        expectedHash: 'deadbeef',
      ),
      throwsA(isA<DownloadException>()),
    );
    expect(File(dest).existsSync(), isFalse);
    expect(File('$dest.part').existsSync(), isFalse);
    expect(requests, 3);
  });

  test('retries server errors', () async {
    failuresLeft = 2;
    final dest = p.join(tempDir(addTearDown).path, 'out.zip');
    await downloader().download(base.resolve('file'), dest);
    expect(requests, 3);
  });

  test('does not retry 404', () async {
    await expectLater(
      downloader().getString(base.resolve('missing')),
      throwsA(
        isA<DownloadException>().having(
          (e) => e.message,
          'message',
          contains('404'),
        ),
      ),
    );
    expect(requests, 1);
  });

  test('getString', () async {
    expect(await downloader().getString(base.resolve('text')), 'hello');
    expect(utf8.encode('hello'), hasLength(5));
  });
}
