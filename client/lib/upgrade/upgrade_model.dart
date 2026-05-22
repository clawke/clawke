/// 升级信息数据模型
class UpgradeInfo {
  /// 最新版本号
  final String version;

  /// 更新日志（Markdown 格式）
  final String changelog;

  /// 发布日期
  final String releaseDate;

  /// 下载链接
  final String downloadUrl;

  /// 升级级别：0=无需升级, 1=可选, 2=强制
  final int upgradeLevel;

  /// Android 应用市场包名（可选）
  final String? marketPackage;

  /// 服务端下发的标题 — Title provided by the server.
  final String title;

  /// 服务端下发的说明 — Message provided by the server.
  final String message;

  /// 服务端下发的升级动作 — Update action provided by the server.
  final String action;

  /// 客户端版本 — Client version reported in compatibility checks.
  final String clientVersion;

  /// 服务端版本 — Server version reported in compatibility checks.
  final String serverVersion;

  const UpgradeInfo({
    required this.version,
    required this.changelog,
    required this.releaseDate,
    required this.downloadUrl,
    required this.upgradeLevel,
    this.marketPackage,
    this.title = '',
    this.message = '',
    this.action = '',
    this.clientVersion = '',
    this.serverVersion = '',
  });

  /// 从 CUP system_status 消息解析
  factory UpgradeInfo.fromSystemStatus(Map<String, dynamic> json) {
    final updateInfo = json['update_info'] as Map<String, dynamic>? ?? {};
    return UpgradeInfo(
      version: updateInfo['version'] as String? ?? '',
      changelog: updateInfo['changelog'] as String? ?? '',
      releaseDate: updateInfo['release_date'] as String? ?? '',
      downloadUrl: updateInfo['download_url'] as String? ?? '',
      upgradeLevel: json['upgrade'] as int? ?? 0,
      marketPackage: updateInfo['market_package'] as String?,
      title: updateInfo['title'] as String? ?? '',
      message: updateInfo['message'] as String? ?? '',
      action: updateInfo['action'] as String? ?? '',
      clientVersion: updateInfo['client_version'] as String? ?? '',
      serverVersion: updateInfo['server_version'] as String? ?? '',
    );
  }

  /// 是否为强制升级
  bool get isForced => upgradeLevel >= 2;

  /// 是否有升级可用
  bool get isAvailable => upgradeLevel > 0;

  /// 是否指向当前语义版本 — Whether this update targets the same semantic version.
  bool targetsSameSemanticVersionAs(String currentVersion) {
    final target = normalizeSemanticVersion(version);
    final current = normalizeSemanticVersion(currentVersion);
    return target.isNotEmpty && target == current;
  }

  /// 规范化语义版本，忽略 build number — Normalize semver and ignore build metadata.
  static String normalizeSemanticVersion(String value) {
    final raw = value.trim().replaceFirst(RegExp(r'^v'), '').split('+').first;
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(raw);
    if (match == null) return '';
    return '${int.parse(match.group(1)!)}.${int.parse(match.group(2)!)}.${int.parse(match.group(3)!)}';
  }

  /// 弹窗去重使用的稳定键 — Stable key used to de-duplicate upgrade prompts.
  String get notificationKey =>
      '$upgradeLevel|$action|$version|$clientVersion|$serverVersion';
}
