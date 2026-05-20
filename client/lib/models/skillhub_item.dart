class SkillHubConfig {
  final String provider;
  final String apiBaseUrl;
  final String skillsPath;
  final String skillPath;

  const SkillHubConfig({
    required this.provider,
    required this.apiBaseUrl,
    required this.skillsPath,
    required this.skillPath,
  });

  factory SkillHubConfig.fromJson(Map<String, dynamic> json) {
    return SkillHubConfig(
      provider: json['provider'] as String? ?? 'nirvana',
      apiBaseUrl: _withoutTrailingSlash(
        json['apiBaseUrl'] as String? ?? 'https://api.clawke.ai',
      ),
      skillsPath:
          json['skillsPath'] as String? ?? '/api/skillhub/v1/skills.json',
      skillPath: json['skillPath'] as String? ?? '/api/skillhub/v1/skill.json',
    );
  }
}

class SkillHubListResult {
  final List<SkillHubItem> items;
  final String? nextCursor;
  final int total;

  const SkillHubListResult({
    required this.items,
    this.nextCursor,
    required this.total,
  });

  factory SkillHubListResult.fromJson(Map<String, dynamic> json) {
    final rawList = json['list'] as List? ?? json['items'] as List? ?? const [];
    final items = rawList
        .whereType<Map>()
        .map((item) => SkillHubItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    return SkillHubListResult(
      items: items,
      nextCursor: json['nextCursor'] as String?,
      total: (json['total'] as num?)?.toInt() ?? items.length,
    );
  }
}

class SkillHubItem {
  final String id;
  final String slug;
  final String name;
  final String summary;
  final String category;
  final List<String> tags;
  final String source;
  final String sourceOwner;
  final String sourceUrl;
  final bool featured;
  final int downloadCount;
  final String version;
  final String changelog;
  final String license;
  final String packageUrl;
  final String packageSha256;
  final int packageSize;
  final List<String> compatibleGateways;
  final String compatibility;
  final String packageType;
  final List<String> packageSkillMdPaths;
  final int updatedAt;
  final String status;
  final String usage;
  final String originalSkillMd;

  const SkillHubItem({
    required this.id,
    required this.slug,
    required this.name,
    required this.summary,
    required this.category,
    required this.tags,
    required this.source,
    required this.sourceOwner,
    required this.sourceUrl,
    required this.featured,
    required this.downloadCount,
    required this.version,
    required this.changelog,
    required this.license,
    required this.packageUrl,
    required this.packageSha256,
    required this.packageSize,
    required this.compatibleGateways,
    required this.compatibility,
    required this.packageType,
    required this.packageSkillMdPaths,
    required this.updatedAt,
    required this.status,
    required this.usage,
    required this.originalSkillMd,
  });

  factory SkillHubItem.fromJson(Map<String, dynamic> json) {
    return SkillHubItem(
      id: _stringValue(json['id']),
      slug: _stringValue(json['slug']),
      name: _stringValue(json['name']),
      summary: _stringValue(json['summary']),
      category: _stringValue(json['category']),
      tags: _stringList(json['tags']),
      source: _stringValue(json['source']),
      sourceOwner: _stringValue(json['sourceOwner']),
      sourceUrl: _stringValue(json['sourceUrl']),
      featured: json['featured'] == true,
      downloadCount: _intValue(json['downloadCount']),
      version: _stringValue(json['version']),
      changelog: _stringValue(json['changelog']),
      license: _stringValue(json['license']),
      packageUrl: _stringValue(json['packageUrl']),
      packageSha256: _stringValue(json['packageSha256']),
      packageSize: _intValue(json['packageSize']),
      compatibleGateways: _stringList(json['compatibleGateways']),
      compatibility: _stringValue(json['compatibility']),
      packageType: _stringValue(json['packageType']),
      packageSkillMdPaths: _stringList(json['packageSkillMdPaths']),
      updatedAt: _intValue(json['updatedAt']),
      status: _stringValue(json['status']),
      usage: _stringValue(json['usage']),
      originalSkillMd: _stringValue(json['originalSkillMd']),
    );
  }
}

class SkillHubInstallResult {
  final String installId;
  final bool installed;
  final String status;
  final String message;

  const SkillHubInstallResult({
    this.installId = '',
    required this.installed,
    required this.status,
    required this.message,
  });

  factory SkillHubInstallResult.fromJson(Map<String, dynamic> json) {
    final status = _stringValue(json['status']);
    final installId = _stringValue(json['installId']).isEmpty
        ? _stringValue(json['install_id'])
        : _stringValue(json['installId']);
    final message = _stringValue(json['message']);
    final installed = json['installed'] == true || status == 'installed';
    return SkillHubInstallResult(
      installId: installId,
      installed: installed,
      status: status.isEmpty ? (installed ? 'installed' : 'accepted') : status,
      message: message.isEmpty ? (installed ? '安装完成' : '安装请求已发送') : message,
    );
  }
}

String _withoutTrailingSlash(String value) {
  return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}

String _stringValue(Object? value) {
  return value?.toString() ?? '';
}

int _intValue(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString()).toList();
}
