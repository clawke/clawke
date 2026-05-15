import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersionInfo {
  const AppVersionInfo({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;

  String get fullVersion =>
      buildNumber.isEmpty ? version : '$version+$buildNumber';
}

final appVersionProvider = FutureProvider<AppVersionInfo>((ref) async {
  final packageInfo = await PackageInfo.fromPlatform();
  return AppVersionInfo(
    version: packageInfo.version,
    buildNumber: packageInfo.buildNumber,
  );
});
