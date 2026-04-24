import 'dart:io';
import 'dart:math';

import 'package:client/services/media_resolver.dart';
import 'package:path/path.dart' as p;

import 'package:flutter/foundation.dart';

/// IM 标准模式：将外部文件复制到 App 缓存目录，确保后续访问不受沙盒限制。
/// 类似微信/Telegram 的本地媒体缓存。
class MediaCacheService {
  static MediaCacheService? _instance;
  late Directory _cacheDir;
  bool _initialized = false;

  MediaCacheService._();

  static MediaCacheService get instance {
    _instance ??= MediaCacheService._();
    return _instance!;
  }

  Future<void>? _initFuture;

  /// 初始化缓存目录（保证只执行一次）
  Future<void> init() {
    _initFuture ??= _doInit();
    return _initFuture!;
  }

  Future<void> _doInit() async {
    if (_initialized) return;
    try {
      _initSyncIfNeeded();
      debugPrint('[MediaCache] ✅ Synchronous INIT SUCCESS: ${_cacheDir.path}');
    } catch (e) {
      debugPrint('[MediaCache] ❌ init failed: $e');
      _initFuture = null; // 允许重试
    }
  }

  /// 同步初始化缓存目录，提取公共逻辑
  void _initSyncIfNeeded() {
    if (_initialized) return;
    final String basePath;
    if (Platform.isMacOS || Platform.isIOS) {
      // macOS/iOS App Sandbox: HOME points to the container data dir
      basePath = p.join(Platform.environment['HOME'] ?? Directory.systemTemp.path, 'Documents');
    } else {
      basePath = Directory.systemTemp.path;
    }

    _cacheDir = Directory(p.join(basePath, 'clawke_media'));
    if (!_cacheDir.existsSync()) {
      _cacheDir.createSync(recursive: true);
    }
    _initialized = true;
  }

  /// 确保父目录存在，返回可写入的 File 对象
  File _getFile(String path) {
    final file = File(path);
    if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
    return file;
  }

  /// 将文件复制到缓存目录，返回缓存路径。
  /// 如果文件已在缓存目录中则直接返回。
  Future<String> cacheFile(String sourcePath) async {
    await init();
    final sourceFile = File(sourcePath);

    // 已经在缓存目录中，无需再复制
    if (sourcePath.startsWith(_cacheDir.path)) {
      return sourcePath;
    }

    final ext = p.extension(sourcePath);
    final cachedPath = p.join(_cacheDir.path, _generateTempName(ext));

    try {
      await sourceFile.copy(_getFile(cachedPath).path);
      debugPrint('[MediaCache] Cached: ${p.basename(sourcePath)} -> $cachedPath');
      return cachedPath;
    } catch (e) {
      debugPrint('[MediaCache] Cache failed for $sourcePath: $e');
      // 回退：返回原路径（可能无法显示，但不会崩溃）
      return sourcePath;
    }
  }

  /// 同步版本（用于现有同步 API）
  String cacheFileSync(String sourcePath) {
    _initSyncIfNeeded();

    if (sourcePath.startsWith(_cacheDir.path)) {
      return sourcePath;
    }

    final ext = p.extension(sourcePath);
    final cachedPath = p.join(_cacheDir.path, _generateTempName(ext));

    try {
      File(sourcePath).copySync(_getFile(cachedPath).path);
      debugPrint('[MediaCache] Cached: ${p.basename(sourcePath)} -> $cachedPath');
      return cachedPath;
    } catch (e) {
      debugPrint('[MediaCache] Cache failed for $sourcePath: $e');
      return sourcePath;
    }
  }

  /// 从字节数据缓存（粘贴的图片等）
  String cacheBytes(List<int> bytes, String fileName) {
    _initSyncIfNeeded();

    final ext = p.extension(fileName).isEmpty ? '.dat' : p.extension(fileName);
    final cachedPath = p.join(_cacheDir.path, _generateTempName(ext));

    _getFile(cachedPath).writeAsBytesSync(bytes);

    debugPrint('[MediaCache] Cached bytes: $fileName -> $cachedPath');
    return cachedPath;
  }

  /// 根据 mediaUrl 查找本地缓存文件（按文件名匹配）
  /// 例: "/api/media/20260317_123456_abcd.png" → 在缓存目录中搜索 "20260317_123456_abcd.png"
  /// 注意：缩略图缓存文件名带 "thumb_" 前缀，不会被原图 URL 误匹配
  String? lookupByMediaUrl(String mediaUrl) {
    if (!_initialized) return null;
    final basename = mediaUrl.split('/').last;
    if (basename.isEmpty) return null;

    // 缩略图 URL 含 /thumb/ → 查找 thumb_ 前缀的缓存文件
    final isThumb = mediaUrl.contains('/thumb/');
    final targetName = isThumb ? 'thumb_$basename' : basename;

    // 精确匹配文件名
    final candidate = File(p.join(_cacheDir.path, targetName));
    if (candidate.existsSync()) return candidate.path;

    return null;
  }

  /// 从 HTTP 下载并缓存到本地，返回本地路径
  Future<String?> downloadAndCache(String url) async {
    await init();
    // 使用纯 Dart IO HttpClient 绕过 macOS ATS 拦截
    // 不用 package:http，因为它走 NSURLSession，会被 ATS 拦截 http:// 明文请求
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..findProxy = (Uri uri) => 'DIRECT';  // 无视系统代理，强行直连局域网
    try {
      final request = await client.getUrl(Uri.parse(url));

      // 注入 Auth Token
      MediaResolver.authHeaders.forEach((key, value) {
        request.headers.add(key, value);
      });

      final response = await request.close().timeout(const Duration(seconds: 15));
      debugPrint('[MediaCache] 📡 HTTP Response for $url: ${response.statusCode}');

      if (response.statusCode == 200) {
        final bytes = <int>[];
        await for (var chunk in response) {
          bytes.addAll(chunk);
        }

        final basename = url.split('/').last;
        final ext = p.extension(basename).isEmpty ? '.dat' : p.extension(basename);
        // 缩略图 URL 含 /thumb/，加前缀区分，避免与原图缓存冲突
        final prefix = url.contains('/thumb/') ? 'thumb_' : '';
        final cachedPath = p.join(_cacheDir.path, basename.isNotEmpty ? '$prefix$basename' : _generateTempName(ext));

        _getFile(cachedPath).writeAsBytesSync(bytes);

        debugPrint('[MediaCache] ✅ Downloaded & cached: $url → $cachedPath (size: ${bytes.length})');
        return cachedPath;
      } else {
        debugPrint('[MediaCache] ❌ HTTP ${response.statusCode}');
      }
    } catch (e, stack) {
      debugPrint('[MediaCache] ❌ Download exception: $url, $e\n$stack');
    } finally {
      client.close();
    }
    return null;
  }

  /// 生成临时文件名：yyyyMMdd_HHmmss_xxxx.ext
  static String _generateTempName(String ext) {
    final now = DateTime.now();
    final date = '${now.year}${_pad(now.month)}${_pad(now.day)}';
    final time = '${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
    final rand = _randomString(4);
    return '${date}_${time}_$rand$ext';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  static final _random = Random();
  static const _chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  static String _randomString(int len) =>
      List.generate(len, (_) => _chars[_random.nextInt(_chars.length)]).join();
}
