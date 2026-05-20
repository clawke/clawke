import 'dart:typed_data';

import 'package:client/providers/staged_attachments_provider.dart';
import 'package:client/services/staged_attachment_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cacheStagedAttachmentForSend', () {
    test('caches path-based attachments through file cache', () {
      final calls = <String>[];

      final path = cacheStagedAttachmentForSend(
        const StagedAttachment(path: '/tmp/screenshot.png', type: 'image'),
        cacheFile: (sourcePath) {
          calls.add(sourcePath);
          return '/cache/screenshot.png';
        },
      );

      expect(path, '/cache/screenshot.png');
      expect(calls, ['/tmp/screenshot.png']);
    });

    test('caches pasted image bytes for mixed messages', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      late List<int> cachedBytes;
      late String cachedName;

      final path = cacheStagedAttachmentForSend(
        StagedAttachment(type: 'image', name: 'paste.png', bytes: bytes),
        cacheBytes: (inputBytes, fileName) {
          cachedBytes = inputBytes;
          cachedName = fileName;
          return '/cache/paste.png';
        },
      );

      expect(path, '/cache/paste.png');
      expect(cachedBytes, bytes);
      expect(cachedName, 'paste.png');
    });

    test('uses fallback name when pasted bytes have no name', () {
      final path = cacheStagedAttachmentForSend(
        StagedAttachment(type: 'image', bytes: Uint8List.fromList([9])),
        fallbackFileName: () => 'fallback.png',
        cacheBytes: (_, fileName) => '/cache/$fileName',
      );

      expect(path, '/cache/fallback.png');
    });
  });
}
