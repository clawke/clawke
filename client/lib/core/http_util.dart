import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'env_config.dart';

/// Clawke Web 服务（clawke.ai）统一 HTTP 请求工具类。
///
/// 复用 rcWorld `HttpUtil.doPost()` 设计模式：
/// - 自动拼接 baseUrl
/// - 自动从 SharedPreferences 读取 uid/securit 注入 Cookie
/// - 统一解析 `{success, actionError, value}` 响应格式
/// - success=false 时抛出 [ApiException]
class HttpUtil {
  /// clawke.ai Web 服务地址（由 EnvConfig 根据环境决定）
  static String get _webBaseUrl => EnvConfig.webBaseUrl;

  /// SharedPreferences keys（与 AuthService 保持一致）
  static const String _kUidKey = 'clawke_auth_uid';
  static const String _kSecuritKey = 'clawke_auth_securit';

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    // 不让 Dio 自动抛异常，我们自己解析响应
    validateStatus: (status) => true,
  ));

  static bool _initialized = false;

  /// 初始化 Dio（仅首次调用时执行）
  static void _initDio() {
    if (_initialized) return;

    // 仅开发环境允许自签名证书
    if (EnvConfig.allowBadCertificates) {
      (_dio.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate = (client) {
        client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
        return client;
      };
    }

    _initialized = true;
  }

  @visibleForTesting
  static void setMockAdapter(HttpClientAdapter adapter) {
    _dio.httpClientAdapter = adapter;
    _initialized = true; // Prevent _initDio from overriding it
  }

  /// 统一 POST 请求。
  ///
  /// [url] 相对路径（如 `/user/emailLogin.json`）或完整 URL。
  /// [data] 请求参数，自动编码为 FormData。
  ///
  /// 返回解析后的响应 Map（包含 success/actionError/value）。
  /// success=false 时抛出 [ApiException]。
  ///
  /// 用法：
  /// ```dart
  /// final result = await HttpUtil.doPost('/user/emailLogin.json', data: {
  ///   'loginId': email,
  ///   'password': password,
  /// });
  /// final user = UserVO.fromJson(result['value']);
  /// ```
  static Future<Map<String, dynamic>> doPost(
    String url, {
    Map<String, dynamic>? data,
  }) async {
    // 1. 拼接 URL
    if (!url.startsWith('http')) {
      url = _webBaseUrl + url;
    }
    debugPrint('[HttpUtil] POST $url');

    try {
      _initDio();

      // 2. FormData 编码
      FormData? formData;
      if (data != null && data.isNotEmpty) {
        formData = FormData.fromMap(data);
      }

      // 3. Cookie 鉴权注入（参考 rcWorld）
      final options = Options();
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString(_kUidKey);
      final securit = prefs.getString(_kSecuritKey);
      if (uid != null && uid.isNotEmpty && securit != null && securit.isNotEmpty) {
        final cookie = '__UID=${Uri.encodeComponent(uid)};'
            '__SECURIT=${Uri.encodeComponent(securit)};';
        options.headers = {'Cookie': cookie};
      }

      // 4. 发起请求
      final response = await _dio.post(
        url,
        data: formData,
        options: options,
      );

      // 5. 解析响应（兼容 String 和 Map 两种返回格式）
      Map<String, dynamic>? jsonResult;
      if (response.data is String && (response.data as String).isNotEmpty) {
        try {
          jsonResult = jsonDecode(response.data) as Map<String, dynamic>;
        } catch (_) {
          // 响应不是 JSON（如 HTML 页面）
        }
      } else if (response.data is Map) {
        jsonResult = Map<String, dynamic>.from(response.data as Map);
      }

      // 非 200 且无法解析 JSON → 直接报状态码错误
      if (response.statusCode != 200 && jsonResult == null) {
        debugPrint('[HttpUtil] ❌ Non-200 status: ${response.statusCode}');
        debugPrint('[HttpUtil] Response headers: ${response.headers}');
        debugPrint('[HttpUtil] Response body: ${response.data}');
        throw ApiException('网络返回状态异常：${response.statusCode}');
      }

      if (jsonResult == null) {
        throw const ApiException('未知的响应格式');
      }

      debugPrint('[HttpUtil] response: $jsonResult');

      // 6. 统一 success/actionError 处理
      if (jsonResult['success'] == true) {
        return jsonResult;
      } else {
        final errorMsg = jsonResult['actionError']?.toString() ?? '请求失败';
        debugPrint('[HttpUtil] error: $errorMsg');
        throw ApiException(errorMsg);
      }
    } on DioException catch (e) {
      final msg = e.type == DioExceptionType.connectionTimeout
          ? '连接超时，请检查网络'
          : e.type == DioExceptionType.receiveTimeout
              ? '服务器响应超时'
              : '网络异常：${e.message}';
      debugPrint('[HttpUtil] DioException: $msg');
      throw ApiException(msg);
    }
  }
}

/// API 请求异常，携带可展示给用户的错误消息。
class ApiException implements Exception {
  final String message;

  const ApiException(this.message);

  @override
  String toString() => message;
}
