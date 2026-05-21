import 'package:client/core/env_config.dart';

class AppUpdatePolicy {
  AppUpdatePolicy._();

  static bool get inAppUpdatesEnabled => !EnvConfig.macOSAppStoreBuild;

  static Map<String, dynamic> buildSyncData({
    required int lastSeq,
    required String appVersion,
    required String platform,
    required String arch,
    bool? inAppUpdatesEnabled,
  }) {
    return <String, dynamic>{
      'last_seq': lastSeq,
      'app_version': appVersion,
      'platform': platform,
      'arch': arch,
    };
  }
}
