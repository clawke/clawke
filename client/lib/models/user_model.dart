/// User and Relay credential models for auth integration.
library;

/// Mirrors the server-side UserVO response.
class UserVO {
  final String uid;
  final String securit;
  final String name;
  final String? loginId;
  final String? photo;
  final bool admin;
  final String? type;
  final bool bindPhone;

  const UserVO({
    required this.uid,
    required this.securit,
    required this.name,
    this.loginId,
    this.photo,
    this.admin = false,
    this.type,
    this.bindPhone = false,
  });

  factory UserVO.fromJson(Map<String, dynamic> json) {
    return UserVO(
      uid: json['uid']?.toString() ?? '',
      securit: json['securit']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      loginId: json['loginId']?.toString(),
      photo: json['photo']?.toString(),
      admin: json['admin'] == 'true' || json['admin'] == true,
      type: json['type']?.toString(),
      bindPhone: json['bindPhone'] == 'true' || json['bindPhone'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'securit': securit,
    'name': name,
    'loginId': loginId,
    'photo': photo,
    'admin': admin ? 'true' : 'false',
    'type': type,
    'bindPhone': bindPhone ? 'true' : 'false',
  };
}

/// Relay connection credentials returned by the Web service.
class RelayCredentials {
  final String token;
  final String relayUrl;

  const RelayCredentials({
    required this.token,
    required this.relayUrl,
  });

  factory RelayCredentials.fromJson(Map<String, dynamic> json) {
    // 兼容旧格式：subdomain + relayServer → relayUrl
    final url = json['relayUrl']?.toString();
    final legacyUrl = (json['subdomain'] != null && json['relayServer'] != null)
        ? 'https://${json['subdomain']}.${json['relayServer']}'
        : null;
    return RelayCredentials(
      token: json['token']?.toString() ?? '',
      relayUrl: url ?? legacyUrl ?? '',
    );
  }
}
