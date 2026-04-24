import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:client/services/media_resolver.dart';
import 'package:client/services/media_cache_service.dart';

/// 三层渐进加载图片组件
///
/// 渲染顺序：
/// 1. thumbHash → 解码为模糊占位图（即时显示，零 HTTP 请求）
/// 2. 本地缓存 → 按 mediaUrl 文件名查找已缓存文件
/// 3. HTTP 下载 → 缓存到本地后显示（发送/接收方只需下载一次）
class ProgressiveImage extends StatefulWidget {
  final String? thumbHash;
  final String? thumbUrl;
  final String? fullUrl;
  final String? localPath;  // 发送方本地缓存路径（优先使用，避免 EXIF 方向问题）
  final int? width;
  final int? height;
  final double maxWidth;
  final double maxHeight;
  final BorderRadius? borderRadius;
  /// 下载缓存成功后的回调，用于将 localPath 写回 DB
  final void Function(String cachedPath)? onCached;

  const ProgressiveImage({
    super.key,
    this.thumbHash,
    this.thumbUrl,
    this.fullUrl,
    this.localPath,
    this.width,
    this.height,
    this.maxWidth = 240,
    this.maxHeight = 320,
    this.borderRadius,
    this.onCached,
  });

  @override
  State<ProgressiveImage> createState() => _ProgressiveImageState();
}

class _ProgressiveImageState extends State<ProgressiveImage> {
  String? _localPath;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(ProgressiveImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thumbUrl != widget.thumbUrl ||
        oldWidget.fullUrl != widget.fullUrl ||
        oldWidget.localPath != widget.localPath) {
      _resolveImage();
    }
  }

  /// 解析图片路径（优先本地文件，其次缩略图）
  ///
  /// 发送方有 localPath → 直接用（Flutter 处理 EXIF 方向）
  /// 接收方无 localPath → 下载 thumbUrl 缩略图
  /// 原图仅在用户点击打开全屏查看时才按需下载。
  Future<void> _resolveImage() async {
    // 1. 发送方：直接用本地缓存文件（保留 EXIF，避免方向问题）
    if (widget.localPath != null && File(widget.localPath!).existsSync()) {
      if (mounted) setState(() => _localPath = widget.localPath);
      return;
    }

    // 2. 接收方：下载缩略图
    final targetUrl = widget.thumbUrl;
    if (targetUrl == null) return;

    // 查本地缓存
    final cached = MediaCacheService.instance.lookupByMediaUrl(targetUrl);
    if (cached != null) {
      if (mounted) setState(() => _localPath = cached);
      return;
    }

    // HTTP 下载缩略图并缓存
    if (_loading) return;
    _loading = true;
    final resolvedUrl = MediaResolver.resolve(targetUrl);
    final downloaded = await MediaCacheService.instance.downloadAndCache(resolvedUrl);
    _loading = false;
    if (mounted && downloaded != null) {
      setState(() => _localPath = downloaded);
      // 写回 DB，下次重建 widget 不再重复下载
      widget.onCached?.call(downloaded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final aspectRatio = _aspectRatio;
    final displayWidth = _constrainedWidth;
    final displayHeight = displayWidth / aspectRatio;

    return GestureDetector(
      onTap: widget.fullUrl != null
          ? () => _showFullImage(context)
          : null,
      child: ClipRRect(
        borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
        child: SizedBox(
          width: displayWidth,
          height: displayHeight.clamp(0, widget.maxHeight),
          child: _buildImage(),
        ),
      ),
    );
  }

  double get _aspectRatio {
    if (widget.width != null && widget.height != null && widget.width! > 0 && widget.height! > 0) {
      return widget.width! / widget.height!;
    }
    return 4 / 3;
  }

  double get _constrainedWidth {
    if (widget.width != null && widget.width! > 0) {
      return widget.width!.toDouble().clamp(80, widget.maxWidth);
    }
    return widget.maxWidth * 0.7;
  }

  Widget _buildImage() {
    // 本地缓存命中 → 直接 Image.file
    if (_localPath != null) {
      return Image.file(
        File(_localPath!),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _buildThumbHashPlaceholder(),
      );
    }

    // 还没加载完 → 显示 ThumbHash 占位
    return _buildThumbHashPlaceholder();
  }

  /// ThumbHash 解码为模糊占位图
  Widget _buildThumbHashPlaceholder() {
    if (widget.thumbHash == null) {
      return Container(
        color: Colors.grey.shade800,
        child: const Center(
          child: Icon(Icons.image, color: Colors.grey, size: 32),
        ),
      );
    }

    try {
      final hashBytes = base64Decode(widget.thumbHash!);
      final image = _thumbHashToImage(hashBytes);
      if (image != null) {
        return Image.memory(
          image,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
      }
    } catch (e) {
      debugPrint('[ProgressiveImage] ThumbHash decode error: $e');
    }

    return Container(
      color: Colors.grey.shade800,
      child: const Center(
        child: Icon(Icons.image, color: Colors.grey, size: 32),
      ),
    );
  }

  /// Full ThumbHash → RGBA decode (based on ThumbHash spec by Evan Wallace)
  ///
  /// Decodes a ~28 byte ThumbHash into a small RGBA image (~32x32px)
  /// and returns it as a BMP for rendering.
  Uint8List? _thumbHashToImage(Uint8List hash) {
    if (hash.length < 5) return null;

    // Parse header
    final h0 = hash[0] | (hash[1] << 8) | (hash[2] << 16) | (hash[3] << 24);
    final h4 = hash[4];

    final lDc = (h0 & 63) / 63.0;
    final pDc = ((h0 >> 6) & 63) / 31.5 - 1.0;
    final qDc = ((h0 >> 12) & 63) / 31.5 - 1.0;
    final lScale = ((h0 >> 18) & 31) / 31.0;
    final hasAlpha = ((h0 >> 23) & 1) != 0;
    final pScale = ((h0 >> 24) & 63) / 63.0;
    final qScale = ((h4) & 63) / 63.0;
    final isLandscape = ((h4 >> 6) & 1) != 0;

    final lx = (isLandscape ? hasAlpha ? 5 : 7 : hasAlpha ? 3 : 5).toInt();
    final ly = (isLandscape ? hasAlpha ? 3 : 5 : hasAlpha ? 5 : 7).toInt();

    // Alpha channel (not fully decoded in this implementation)
    if (hasAlpha) {
      // Skip alpha handling for now — treated as fully opaque
    }

    // Decode AC coefficients
    int index = 5;
    int bit = 0;

    double decodeAc(double scale) {
      if (index >= hash.length) return 0;
      final byte = hash[index];
      double val;
      if (bit == 0) {
        val = (byte & 15) / 7.5 - 1.0;
        bit = 4;
      } else {
        val = (byte >> 4) / 7.5 - 1.0;
        bit = 0;
        index++;
      }
      return val * scale;
    }

    // Read L channel AC
    final lAc = <double>[];
    for (int i = 0; i < lx * ly - 1; i++) {
      lAc.add(decodeAc(lScale));
    }

    // Read P channel AC
    const px = 3, py = 3;
    final pAc = <double>[];
    for (int i = 0; i < px * py - 1; i++) {
      pAc.add(decodeAc(pScale));
    }

    // Read Q channel AC
    const qx = 3, qy = 3;
    final qAc = <double>[];
    for (int i = 0; i < qx * qy - 1; i++) {
      qAc.add(decodeAc(qScale));
    }

    // Reconstruct image
    final w = lx > ly ? 32 : (32 * lx / ly).round();
    final h = lx > ly ? (32 * ly / lx).round() : 32;
    final ww = w.clamp(1, 32);
    final hh = h.clamp(1, 32);
    final pixels = Uint8List(ww * hh * 4);

    for (int y = 0; y < hh; y++) {
      for (int x = 0; x < ww; x++) {
        // L channel: DC + AC via DCT
        double l = lDc;
        int acIdx = 0;
        for (int cy = 0; cy < ly; cy++) {
          for (int cx = 0; cx < lx; cx++) {
            if (cx == 0 && cy == 0) continue;
            final cosX = _cosLut(cx, x, ww);
            final cosY = _cosLut(cy, y, hh);
            if (acIdx < lAc.length) {
              l += lAc[acIdx] * cosX * cosY;
            }
            acIdx++;
          }
        }

        // P channel
        double p = pDc;
        acIdx = 0;
        for (int cy = 0; cy < py; cy++) {
          for (int cx = 0; cx < px; cx++) {
            if (cx == 0 && cy == 0) continue;
            final cosX = _cosLut(cx, x, ww);
            final cosY = _cosLut(cy, y, hh);
            if (acIdx < pAc.length) {
              p += pAc[acIdx] * cosX * cosY;
            }
            acIdx++;
          }
        }

        // Q channel
        double q = qDc;
        acIdx = 0;
        for (int cy = 0; cy < qy; cy++) {
          for (int cx = 0; cx < qx; cx++) {
            if (cx == 0 && cy == 0) continue;
            final cosX = _cosLut(cx, x, ww);
            final cosY = _cosLut(cy, y, hh);
            if (acIdx < qAc.length) {
              q += qAc[acIdx] * cosX * cosY;
            }
            acIdx++;
          }
        }

        // LPQ → RGB
        final r = ((l + 0.6774 * q) * 255).clamp(0, 255).toInt();
        final g = ((l - 0.1546 * p - 0.3213 * q) * 255).clamp(0, 255).toInt();
        final b = ((l + 0.8165 * p) * 255).clamp(0, 255).toInt();

        final offset = (y * ww + x) * 4;
        pixels[offset] = r;
        pixels[offset + 1] = g;
        pixels[offset + 2] = b;
        pixels[offset + 3] = 255;
      }
    }

    return _createBmp(ww, hh, pixels);
  }

  /// Cosine lookup for DCT
  static double _cosLut(int freq, int pos, int size) {
    return math.cos(freq * pos * 3.14159265 / size);
  }

  /// Create BMP from RGBA pixel data
  Uint8List _createBmp(int w, int h, Uint8List rgba) {
    final rowBytes = w * 3;
    final padding = (4 - (rowBytes % 4)) % 4;
    final rowStride = rowBytes + padding;
    final dataSize = rowStride * h;
    final fileSize = 54 + dataSize;
    final bmp = Uint8List(fileSize);

    // BMP file header (14 bytes)
    bmp[0] = 0x42; // 'B'
    bmp[1] = 0x4D; // 'M'
    bmp[2] = fileSize & 0xFF;
    bmp[3] = (fileSize >> 8) & 0xFF;
    bmp[4] = (fileSize >> 16) & 0xFF;
    bmp[5] = (fileSize >> 24) & 0xFF;
    bmp[10] = 54; // pixel data offset

    // DIB header (40 bytes)
    bmp[14] = 40; // header size
    bmp[18] = w & 0xFF;
    bmp[19] = (w >> 8) & 0xFF;
    // BMP stores height bottom-up, use negative for top-down
    final negH = -h;
    bmp[22] = negH & 0xFF;
    bmp[23] = (negH >> 8) & 0xFF;
    bmp[24] = (negH >> 16) & 0xFF;
    bmp[25] = (negH >> 24) & 0xFF;
    bmp[26] = 1; // planes
    bmp[28] = 24; // bits per pixel

    // Pixel data (BGR, top-down)
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final srcOff = (y * w + x) * 4;
        final dstOff = 54 + y * rowStride + x * 3;
        bmp[dstOff] = rgba[srcOff + 2]; // B
        bmp[dstOff + 1] = rgba[srcOff + 1]; // G
        bmp[dstOff + 2] = rgba[srcOff]; // R
      }
    }

    return bmp;
  }

  /// 全屏查看原图（按需下载）
  void _showFullImage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FullImageViewer(
          fullUrl: MediaResolver.resolve(widget.fullUrl!),
          // 只传发送方原文件，不传下载的缩略图（缩略图文件名含 thumb_）
          localFullPath: (widget.localPath != null && !widget.localPath!.split('/').last.startsWith('thumb_'))
              ? widget.localPath
              : null,
          thumbCachePath: _localPath, // 已缓存的缩略图路径
        ),
      ),
    );
  }
}

/// 全屏图片查看器（懒加载原图）
///
/// 打开时先显示已缓存的缩略图，后台下载原图，下载完成替换显示。
class _FullImageViewer extends StatefulWidget {
  final String fullUrl;
  final String? localFullPath;
  final String? thumbCachePath;

  const _FullImageViewer({required this.fullUrl, this.localFullPath, this.thumbCachePath});

  @override
  State<_FullImageViewer> createState() => _FullImageViewerState();
}

class _FullImageViewerState extends State<_FullImageViewer> {
  String? _fullImagePath;
  bool _downloading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 延迟到 build 完成后执行，避免 debugPrint → DebugLogNotifier 在 build 阶段崩溃
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFullImage());
  }

  Future<void> _loadFullImage() async {
    // 0. 发送方已有本地原图 → 直接使用，无需下载
    if (widget.localFullPath != null && File(widget.localFullPath!).existsSync()) {
      if (mounted) setState(() => _fullImagePath = widget.localFullPath);
      return;
    }

    // 1. 先确保缓存已初始化，再查缓存
    await MediaCacheService.instance.init();
    final cached = MediaCacheService.instance.lookupByMediaUrl(widget.fullUrl);
    if (cached != null) {
      if (mounted) setState(() => _fullImagePath = cached);
      return;
    }

    // 2. 后台下载原图
    setState(() => _downloading = true);
    final downloaded = await MediaCacheService.instance.downloadAndCache(widget.fullUrl);
    if (!mounted) return;
    if (downloaded != null) {
      setState(() {
        _fullImagePath = downloaded;
        _downloading = false;
      });
    } else {
      setState(() {
        _error = '原图加载失败';
        _downloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 图片：优先原图，否则缩略图
            InteractiveViewer(
              child: _buildDisplayImage(),
            ),
            // 下载中指示器
            if (_downloading)
              Positioned(
                bottom: 48,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white70,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('加载原图...', style: TextStyle(color: Colors.white70, fontSize: Theme.of(context).textTheme.labelSmall!.fontSize)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisplayImage() {
    // 优先显示已下载的原图
    if (_fullImagePath != null) {
      return Image.file(File(_fullImagePath!), fit: BoxFit.contain);
    }

    // 原图未就绪 → 显示缩略图
    if (widget.thumbCachePath != null) {
      return Image.file(File(widget.thumbCachePath!), fit: BoxFit.contain);
    }

    // 都没有
    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image, color: Colors.grey, size: 48),
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Colors.grey.shade400)),
        ],
      );
    }

    return const Center(child: CircularProgressIndicator());
  }
}
