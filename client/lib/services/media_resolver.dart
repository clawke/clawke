/// 媒体 URL 解析器
///
/// 将 CS 返回的相对路径（如 /api/media/xxx.png）转换为完整的 HTTP URL。
/// baseUrl 由 ServerConfig 在启动时设置。
class MediaResolver {
  static String _baseUrl = 'http://127.0.0.1:8780';
  static String _token = '';

  /// 设置 HTTP 基础 URL（由 ServerConfig 驱动）
  static void setBaseUrl(String url) {
    // 去掉末尾斜杠
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// 设置认证 Token
  static void setToken(String token) => _token = token;

  /// 当前 HTTP 基础 URL
  static String get baseUrl => _baseUrl;

  /// HTTP 认证 Headers（供 dio / http 请求使用）
  /// 两边都空 = 不需要认证 header
  static Map<String, String> get authHeaders =>
      _token.isNotEmpty ? {'Authorization': 'Bearer $_token'} : {};

  /// 将相对路径解析为完整 URL
  ///
  /// 示例：
  /// - `/api/media/xxx.png` → `http://127.0.0.1:8780/api/media/xxx.png`
  /// - `http://...` → 原样返回（已是完整 URL）
  static String resolve(String relativePath) {
    if (relativePath.startsWith('http://') ||
        relativePath.startsWith('https://')) {
      return relativePath;
    }
    return '$_baseUrl$relativePath';
  }

  /// 判断路径是否是媒体 URL（非本地文件路径）
  static bool isMediaUrl(String path) {
    return path.startsWith('/api/media/') ||
        path.startsWith('http://') ||
        path.startsWith('https://');
  }
}
