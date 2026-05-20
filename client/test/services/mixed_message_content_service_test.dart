import 'dart:convert';
import 'dart:typed_data';

import 'package:client/providers/staged_attachments_provider.dart';
import 'package:client/services/media_upload_service.dart';
import 'package:client/services/mixed_message_content_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildUploadedMixedContentJson', () {
    test(
      'keeps pasted image bytes when text and image are sent together',
      () async {
        final uploadedPaths = <String>[];
        List<int>? cachedBytes;
        String? cachedName;

        final contentJson = await buildUploadedMixedContentJson(
          'can you see this screenshot?',
          [
            StagedAttachment(
              type: 'image',
              name: 'paste.png',
              bytes: Uint8List.fromList([1, 2, 3]),
            ),
          ],
          cacheBytes: (bytes, fileName) {
            cachedBytes = bytes;
            cachedName = fileName;
            return '/cache/paste.png';
          },
          upload: (file) async {
            uploadedPaths.add(file.path);
            return const MediaUploadResult(
              mediaId: 'media-1',
              mediaUrl: '/api/media/paste.png',
              mediaType: 'image/png',
              thumbUrl: '/api/media/thumb/paste.jpg',
              thumbHash: 'thumbhash',
              width: 120,
              height: 80,
            );
          },
        );

        expect(cachedBytes, [1, 2, 3]);
        expect(cachedName, 'paste.png');
        expect(uploadedPaths, ['/cache/paste.png']);

        final decoded = jsonDecode(contentJson) as Map<String, dynamic>;
        expect(decoded['text'], 'can you see this screenshot?');

        final attachments = decoded['attachments'] as List<dynamic>;
        expect(attachments, hasLength(1));

        final image = attachments.single as Map<String, dynamic>;
        expect(image['type'], 'image');
        expect(image['mediaUrl'], '/api/media/paste.png');
        expect(image['localPath'], '/cache/paste.png');
        expect(image.containsKey('path'), isFalse);
      },
    );
  });
}
