import 'package:client/models/user_model.dart';

/// 账号摘要 — 用于切换账号页展示和凭证恢复。
///
/// 存储在 SharedPreferences 中（跨用户可读），
/// 包含最少的凭证信息用于切换时恢复登录态。
class AccountSummary {
  final String uid;
  final String securit;
  final String name;
  final String? loginId;
  final String? photo;

  const AccountSummary({
    required this.uid,
    required this.securit,
    required this.name,
    this.loginId,
    this.photo,
  });

  factory AccountSummary.fromJson(Map<String, dynamic> json) {
    return AccountSummary(
      uid: json['uid'] as String? ?? '',
      securit: json['securit'] as String? ?? '',
      name: json['name'] as String? ?? '',
      loginId: json['loginId'] as String?,
      photo: json['photo'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'securit': securit,
    'name': name,
    'loginId': loginId,
    'photo': photo,
  };

  /// 从完整的 UserVO 创建摘要
  factory AccountSummary.fromUser(UserVO user) {
    return AccountSummary(
      uid: user.uid,
      securit: user.securit,
      name: user.name,
      loginId: user.loginId,
      photo: user.photo,
    );
  }
}
