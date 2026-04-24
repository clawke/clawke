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

  const UpgradeInfo({
    required this.version,
    required this.changelog,
    required this.releaseDate,
    required this.downloadUrl,
    required this.upgradeLevel,
    this.marketPackage,
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
    );
  }

  /// 是否为强制升级
  bool get isForced => upgradeLevel >= 2;

  /// 是否有升级可用
  bool get isAvailable => upgradeLevel > 0;
}
