import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// MediaCacheService 的核心缓存逻辑测试
/// 测试 thumb_ 前缀机制和 lookupByMediaUrl 区分缩略图/原图
///
/// 由于 MediaCacheService 是单例且依赖文件系统，这里直接测试其核心逻辑
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('media_cache_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  // ── 辅助函数：模拟 downloadAndCache 的文件名生成逻辑 ──
  String simulateDownloadCachePath(String url, String cacheDir) {
    final basename = url.split('/').last;
    final prefix = url.contains('/thumb/') ? 'thumb_' : '';
    return p.join(cacheDir, '$prefix$basename');
  }

  // ── 辅助函数：模拟 lookupByMediaUrl 逻辑 ──
  String? simulateLookup(String mediaUrl, String cacheDir) {
    final basename = mediaUrl.split('/').last;
    if (basename.isEmpty) return null;

    final isThumb = mediaUrl.contains('/thumb/');
    final targetName = isThumb ? 'thumb_$basename' : basename;

    final candidate = File(p.join(cacheDir, targetName));
    if (candidate.existsSync()) return candidate.path;

    return null;
  }

  group('downloadAndCache 文件名前缀', () {
    test('原图 URL → 不加前缀', () {
      final path = simulateDownloadCachePath(
        'http://127.0.0.1:8780/api/media/1774417201840_8667be55.jpg',
        tempDir.path,
      );
      expect(p.basename(path), '1774417201840_8667be55.jpg');
      expect(p.basename(path).startsWith('thumb_'), isFalse);
    });

    test('缩略图 URL（含 /thumb/）→ 加 thumb_ 前缀', () {
      final path = simulateDownloadCachePath(
        'http://127.0.0.1:8780/api/media/thumb/1774417201840_8667be55.jpg',
        tempDir.path,
      );
      expect(p.basename(path), 'thumb_1774417201840_8667be55.jpg');
      expect(p.basename(path).startsWith('thumb_'), isTrue);
    });

    test('原图和缩略图文件名不冲突', () {
      final fullPath = simulateDownloadCachePath(
        'http://host/api/media/abc.jpg',
        tempDir.path,
      );
      final thumbPath = simulateDownloadCachePath(
        'http://host/api/media/thumb/abc.jpg',
        tempDir.path,
      );
      expect(fullPath, isNot(thumbPath),
          reason: '原图和缩略图缓存路径必须不同');
      expect(p.basename(fullPath), 'abc.jpg');
      expect(p.basename(thumbPath), 'thumb_abc.jpg');
    });
  });

  group('lookupByMediaUrl 缓存查找', () {
    test('查找原图 → 匹配不带 thumb_ 前缀的文件', () {
      // 模拟缓存目录中有原图
      File(p.join(tempDir.path, 'abc.jpg')).writeAsStringSync('full');
      File(p.join(tempDir.path, 'thumb_abc.jpg')).writeAsStringSync('thumb');

      final result = simulateLookup(
        'http://host/api/media/abc.jpg',
        tempDir.path,
      );
      expect(result, isNotNull);
      expect(p.basename(result!), 'abc.jpg',
          reason: '原图 URL 应匹配不带 thumb_ 前缀的文件');
    });

    test('查找缩略图 → 匹配带 thumb_ 前缀的文件', () {
      File(p.join(tempDir.path, 'abc.jpg')).writeAsStringSync('full');
      File(p.join(tempDir.path, 'thumb_abc.jpg')).writeAsStringSync('thumb');

      final result = simulateLookup(
        'http://host/api/media/thumb/abc.jpg',
        tempDir.path,
      );
      expect(result, isNotNull);
      expect(p.basename(result!), 'thumb_abc.jpg',
          reason: '缩略图 URL 应匹配带 thumb_ 前缀的文件');
    });

    test('原图未缓存 → 返回 null（不会误匹配缩略图）', () {
      // 只有缩略图，没有原图
      File(p.join(tempDir.path, 'thumb_abc.jpg')).writeAsStringSync('thumb');

      final result = simulateLookup(
        'http://host/api/media/abc.jpg',
        tempDir.path,
      );
      expect(result, isNull,
          reason: '只有缩略图缓存时，查找原图应返回 null');
    });

    test('缩略图未缓存 → 返回 null（不会误匹配原图）', () {
      // 只有原图，没有缩略图
      File(p.join(tempDir.path, 'abc.jpg')).writeAsStringSync('full');

      final result = simulateLookup(
        'http://host/api/media/thumb/abc.jpg',
        tempDir.path,
      );
      expect(result, isNull,
          reason: '只有原图缓存时，查找缩略图应返回 null');
    });

    test('空 basename → 返回 null', () {
      final result = simulateLookup(
        'http://host/api/media/',
        tempDir.path,
      );
      expect(result, isNull);
    });
  });

  group('localFullPath 过滤逻辑', () {
    // 模拟 _showFullImage 中的 localFullPath 过滤
    String? filterLocalFullPath(String? localPath) {
      if (localPath == null) return null;
      if (localPath.split('/').last.startsWith('thumb_')) return null;
      return localPath;
    }

    test('发送方原图路径 → 通过', () {
      final result = filterLocalFullPath(
        '/Users/samy/Library/Containers/com.clawke.client/Data/tmp/clawke_media/20260325_134001_1doe.jpg',
      );
      expect(result, isNotNull,
          reason: '发送方原图文件名不含 thumb_，应该传给 localFullPath');
    });

    test('下载的缩略图路径 → 过滤掉', () {
      final result = filterLocalFullPath(
        '/Users/samy/Library/Containers/com.clawke.client/Data/tmp/clawke_media/thumb_1774417201840_8667be55.jpg',
      );
      expect(result, isNull,
          reason: '缩略图文件名含 thumb_，不应传给 localFullPath');
    });

    test('双重 thumb_ 前缀 → 过滤掉', () {
      final result = filterLocalFullPath(
        '/path/clawke_media/thumb_thumb_abc.jpg',
      );
      expect(result, isNull,
          reason: '双重 thumb_ 前缀也应被过滤');
    });

    test('null path → 返回 null', () {
      expect(filterLocalFullPath(null), isNull);
    });

    test('无路径分隔符 → 正确处理', () {
      expect(filterLocalFullPath('thumb_abc.jpg'), isNull);
      expect(filterLocalFullPath('abc.jpg'), 'abc.jpg');
    });
  });

  group('端到端场景', () {
    test('完整流程：缩略图缓存不干扰原图查找', () {
      // 1. 接收方下载缩略图
      const thumbUrl = 'http://host/api/media/thumb/photo123.jpg';
      final thumbCachePath = simulateDownloadCachePath(thumbUrl, tempDir.path);
      File(thumbCachePath).writeAsStringSync('tiny thumb data');
      expect(p.basename(thumbCachePath), 'thumb_photo123.jpg');

      // 2. 查找原图缓存 → 应该找不到（缩略图不算原图）
      const fullUrl = 'http://host/api/media/photo123.jpg';
      final cachedFull = simulateLookup(fullUrl, tempDir.path);
      expect(cachedFull, isNull,
          reason: '缩略图缓存不应被当作原图');

      // 3. 下载原图
      final fullCachePath = simulateDownloadCachePath(fullUrl, tempDir.path);
      File(fullCachePath).writeAsStringSync('large full image data');
      expect(p.basename(fullCachePath), 'photo123.jpg');

      // 4. 再次查找原图缓存 → 应该找到
      final cachedFull2 = simulateLookup(fullUrl, tempDir.path);
      expect(cachedFull2, isNotNull);
      expect(p.basename(cachedFull2!), 'photo123.jpg');

      // 5. 缩略图缓存仍然独立存在
      final cachedThumb = simulateLookup(thumbUrl, tempDir.path);
      expect(cachedThumb, isNotNull);
      expect(p.basename(cachedThumb!), 'thumb_photo123.jpg');

      // 6. 两个文件都存在且互不干扰
      expect(File(thumbCachePath).readAsStringSync(), 'tiny thumb data');
      expect(File(fullCachePath).readAsStringSync(), 'large full image data');
    });

    test('完整流程：localFullPath 过滤下载后写回的缩略图路径', () {
      // 模拟接收方场景：
      // 1. 下载缩略图 → 缓存为 thumb_xxx.jpg
      // 2. onCached 写回 DB → localPath = thumb_xxx.jpg
      // 3. 点击查看原图 → localFullPath 应被过滤

      final thumbCachePath = p.join(tempDir.path, 'thumb_photo456.jpg');
      File(thumbCachePath).writeAsStringSync('thumb');

      // 模拟 onCached 写回的 localPath
      final localPathFromDb = thumbCachePath;

      // 模拟 _showFullImage 中的过滤
      final localFullPath = (localPathFromDb.split('/').last.startsWith('thumb_'))
          ? null
          : localPathFromDb;

      expect(localFullPath, isNull,
          reason: '接收方的 localPath 是缩略图，不应传给 localFullPath');
    });
  });
}
