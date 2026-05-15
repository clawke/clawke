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
    final updatesEnabled =
        inAppUpdatesEnabled ?? AppUpdatePolicy.inAppUpdatesEnabled;
    final data = <String, dynamic>{'last_seq': lastSeq};
    if (!updatesEnabled) return data;

    data.addAll({
      'app_version': appVersion,
      'platform': platform,
      'arch': arch,
    });
    return data;
  }
}
