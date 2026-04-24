/// 环境配置 —— 修改此文件切换环境。
class EnvConfig {
  EnvConfig._();

  /// clawke.ai Web 服务地址
  static const String webBaseUrl = 'https://clawke.ai';

  /// 是否允许自签名证书（本地开发时设为 true）
  static const bool allowBadCertificates = false;
}
