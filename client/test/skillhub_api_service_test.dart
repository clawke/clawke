import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:client/models/skillhub_item.dart';
import 'package:client/services/media_resolver.dart';
import 'package:client/services/skillhub_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses longer receive timeout for cloud SkillHub catalog calls', () {
    expect(skillHubCloudReceiveTimeout, const Duration(seconds: 60));
    expect(skillHubLocalReceiveTimeout, const Duration(seconds: 10));
  });

  test('loads config locally then lists SkillHub items from Nirvana', () async {
    MediaResolver.setToken('relay-token');
    addTearDown(() => MediaResolver.setToken(''));

    final localDio = Dio();
    final cloudDio = Dio();
    final cloudRequests = <RequestOptions>[];

    localDio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
      expect(options.path, '/api/skillhub/config');
      return _jsonResponse({
        'provider': 'nirvana',
        'apiBaseUrl': 'https://local.clawke.ai',
        'skillsPath': '/api/skillhub/v1/skills.json',
        'skillPath': '/api/skillhub/v1/skill.json',
      });
    });
    cloudDio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
      cloudRequests.add(options);
      return _jsonResponse({
        'success': true,
        'value': {
          'list': [
            {
              'id': 204,
              'slug': 'github-helper',
              'name': 'GitHub Helper',
              'summary': 'GitHub workflow helper',
              'category': 'coding',
              'tags': ['github', 'code'],
              'featured': true,
              'downloadCount': 1200,
              'version': '1.2.1',
              'packageUrl': 'https://local.clawke.ai/upload/package.zip',
              'packageSha256': 'sha256:abc',
              'packageSize': 45678,
              'compatibleGateways': ['openclaw'],
              'compatibility': 'compatible',
              'packageType': 'bundle',
              'updatedAt': 1778664000000,
              'status': 'published',
            },
          ],
          'nextCursor': 'cursor-1',
          'total': 1,
        },
      });
    });

    final service = SkillHubApiService(localDio: localDio, cloudDio: cloudDio);

    final result = await service.listSkills(
      query: 'git',
      category: 'coding',
      tag: 'github',
      featured: true,
      gatewayType: 'openclaw',
      limit: 20,
      cursor: 'cursor-0',
    );

    expect(result.nextCursor, 'cursor-1');
    expect(result.total, 1);
    expect(result.items.single.id, '204');
    expect(result.items.single.category, 'coding');
    expect(result.items.single.tags, ['github', 'code']);
    expect(result.items.single.featured, isTrue);
    expect(result.items.single.downloadCount, 1200);
    expect(result.items.single.compatibleGateways, ['openclaw']);
    expect(
      cloudRequests.single.uri.toString(),
      'https://local.clawke.ai/api/skillhub/v1/skills.json?query=git&category=coding&tag=github&featured=true&gatewayType=openclaw&limit=20&cursor=cursor-0&sort=downloads',
    );
    expect(cloudRequests.single.headers['Authorization'], 'Bearer relay-token');
  });

  test(
    'lowercases category query parameter for SkillHub catalog calls',
    () async {
      final cloudRequests = <RequestOptions>[];
      final service = SkillHubApiService(
        localDio: _dioWithJson({
          'provider': 'nirvana',
          'apiBaseUrl': 'https://local.clawke.ai',
          'skillsPath': '/api/skillhub/v1/skills.json',
          'skillPath': '/api/skillhub/v1/skill.json',
        }),
        cloudDio: _dioWithHandler((options) async {
          cloudRequests.add(options);
          return _jsonResponse({
            'success': true,
            'value': {'list': []},
          });
        }),
      );

      await service.listSkills(category: 'Coding', limit: 30);

      expect(cloudRequests.single.uri.queryParameters['category'], 'coding');
    },
  );

  test('throws readable error when Nirvana JsonResult fails', () async {
    final service = SkillHubApiService(
      localDio: _dioWithJson({
        'provider': 'nirvana',
        'apiBaseUrl': 'https://local.clawke.ai',
        'skillsPath': '/api/skillhub/v1/skills.json',
        'skillPath': '/api/skillhub/v1/skill.json',
      }),
      cloudDio: _dioWithJson({'success': false, 'actionError': 'rate_limited'}),
    );

    expect(
      () => service.listSkills(),
      throwsA(
        isA<SkillHubApiException>().having(
          (error) => error.message,
          'message',
          'rate_limited',
        ),
      ),
    );
  });

  test('maps cloud receive timeout to stable SkillHub error', () async {
    final service = SkillHubApiService(
      localDio: _dioWithJson({
        'provider': 'nirvana',
        'apiBaseUrl': 'https://local.clawke.ai',
        'skillsPath': '/api/skillhub/v1/skills.json',
        'skillPath': '/api/skillhub/v1/skill.json',
      }),
      cloudDio: _dioWithHandler((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
          message: 'The request took longer than 0:00:20.000000',
        );
      }),
    );

    await expectLater(
      service.listSkills(),
      throwsA(
        isA<SkillHubApiException>()
            .having(
              (error) => error.actionError,
              'actionError',
              'receive_timeout',
            )
            .having(
              (error) => error.message,
              'message',
              'SkillHub request timed out',
            ),
      ),
    );
  });

  test('parses SkillHub detail fields from Nirvana', () async {
    final service = SkillHubApiService(
      localDio: _dioWithJson({
        'provider': 'nirvana',
        'apiBaseUrl': 'https://local.clawke.ai',
        'skillsPath': '/api/skillhub/v1/skills.json',
        'skillPath': '/api/skillhub/v1/skill.json',
      }),
      cloudDio: _dioWithJson({
        'success': true,
        'value': {
          'id': 204,
          'name': 'GitHub Helper',
          'category': 'coding',
          'tags': ['github'],
          'featured': true,
          'downloadCount': 1200,
          'compatibleGateways': ['openclaw'],
          'packageType': 'bundle',
          'packageSkillMdPaths': ['SKILL.md'],
          'packageUrl': 'https://local.clawke.ai/upload/package.zip',
          'originalSkillMd': '# GitHub Helper',
        },
      }),
    );

    final detail = await service.getSkill('204');

    expect(detail.id, '204');
    expect(detail.downloadCount, 1200);
    expect(detail.packageSkillMdPaths, ['SKILL.md']);
    expect(detail.packageUrl, 'https://local.clawke.ai/upload/package.zip');
    expect(detail.originalSkillMd, '# GitHub Helper');
  });

  test(
    'posts SkillHub install request to local server and parses result',
    () async {
      late RequestOptions request;
      final service = SkillHubApiService(
        localDio: _dioWithHandler((options) async {
          request = options;
          return _jsonResponse({
            'success': true,
            'value': {
              'installed': true,
              'status': 'installed',
              'message': '安装完成',
            },
          });
        }),
        cloudDio: _dioWithJson({'success': true, 'value': {}}),
      );

      final result = await service.installSkill(_skillHubItem());

      expect(request.method, 'POST');
      expect(request.path, '/api/skillhub/install');
      expect(request.data, {
        'slug': 'github-helper',
        'source': 'clawhub',
        'installMode': 'auto',
      });
      expect(result.installed, isTrue);
      expect(result.status, 'installed');
      expect(result.message, '安装完成');
    },
  );

  test(
    'posts gateway native retry only after fallback gateway selection',
    () async {
      late RequestOptions request;
      final service = SkillHubApiService(
        localDio: _dioWithHandler((options) async {
          request = options;
          return _jsonResponse({
            'success': true,
            'value': {
              'installId': 'skillhub_1',
              'installed': false,
              'status': 'accepted',
              'message': 'Gateway 原生安装已提交',
            },
          }, statusCode: 202);
        }),
        cloudDio: _dioWithJson({'success': true, 'value': {}}),
      );

      final result = await service.installSkill(
        _skillHubItem(),
        gatewayId: 'hermes',
        installMode: 'gateway_native',
      );

      expect(request.data, {
        'slug': 'github-helper',
        'source': 'clawhub',
        'installMode': 'gateway_native',
        'gateway_id': 'hermes',
      });
      expect(result.installId, 'skillhub_1');
    },
  );

  test('parses accepted SkillHub install response with installId', () async {
    final service = SkillHubApiService(
      localDio: _dioWithHandler((_) async {
        return _jsonResponse({
          'success': true,
          'value': {
            'installId': 'skillhub_1',
            'installed': false,
            'status': 'accepted',
            'message': '安装任务已提交',
          },
        }, statusCode: 202);
      }),
      cloudDio: _dioWithJson({'success': true, 'value': {}}),
    );

    final result = await service.installSkill(_skillHubItem());

    expect(result.installId, 'skillhub_1');
    expect(result.installed, isFalse);
    expect(result.status, 'accepted');
    expect(result.message, '安装任务已提交');
  });

  test('throws readable error when local install fails', () async {
    final service = SkillHubApiService(
      localDio: _dioWithJson({
        'success': false,
        'actionError': 'gateway_not_connected',
      }),
      cloudDio: _dioWithJson({'success': true, 'value': {}}),
    );

    expect(
      () => service.installSkill(_skillHubItem()),
      throwsA(
        isA<SkillHubApiException>().having(
          (error) => error.message,
          'message',
          'gateway_not_connected',
        ),
      ),
    );
  });

  test(
    'parses non-2xx local JsonResult error instead of DioException',
    () async {
      final service = SkillHubApiService(
        localDio: _dioWithHandler((_) async {
          return _jsonResponse({
            'success': false,
            'actionError': 'account_required',
            'message':
                'gateway_id is required when gateway native install is needed.',
          }, statusCode: 400);
        }),
        cloudDio: _dioWithJson({'success': true, 'value': {}}),
      );

      await expectLater(
        service.installSkill(_skillHubItem()),
        throwsA(
          isA<SkillHubApiException>()
              .having(
                (error) => error.actionError,
                'actionError',
                'account_required',
              )
              .having(
                (error) => error.message,
                'message',
                'gateway_id is required when gateway native install is needed.',
              ),
        ),
      );
    },
  );

  test(
    'preserves fallback gateway details from local install failure',
    () async {
      final service = SkillHubApiService(
        localDio: _dioWithJson({
          'success': false,
          'actionError': 'fallback_gateway_required',
          'message': '请选择要安装到的 Gateway',
          'details': {
            'gateways': [
              {
                'gatewayId': 'hermes',
                'label': 'Hermes',
                'gatewayType': 'hermes',
              },
            ],
          },
        }),
        cloudDio: _dioWithJson({'success': true, 'value': {}}),
      );

      expect(
        () => service.installSkill(_skillHubItem()),
        throwsA(
          isA<SkillHubApiException>()
              .having(
                (error) => error.actionError,
                'actionError',
                'fallback_gateway_required',
              )
              .having(
                (error) => error.fallbackGateways.single.gatewayId,
                'gatewayId',
                'hermes',
              ),
        ),
      );
    },
  );
}

Dio _dioWithJson(Map<String, Object?> payload) {
  return _dioWithHandler((_) async => _jsonResponse(payload));
}

Dio _dioWithHandler(Future<ResponseBody> Function(RequestOptions) handler) {
  final dio = Dio();
  dio.httpClientAdapter = _FakeHttpClientAdapter(handler);
  return dio;
}

SkillHubItem _skillHubItem() {
  return const SkillHubItem(
    id: '204',
    slug: 'github-helper',
    name: 'GitHub Helper',
    summary: 'GitHub workflow helper',
    category: 'coding',
    tags: ['github'],
    source: 'clawhub',
    sourceOwner: 'garrytan',
    sourceUrl: 'https://clawhub.ai/garrytan/github-helper',
    featured: true,
    downloadCount: 1200,
    version: '1.2.1',
    changelog: '',
    license: '',
    packageUrl: 'https://local.clawke.ai/upload/package.zip',
    packageSha256: 'sha256:abc',
    packageSize: 45678,
    compatibleGateways: ['openclaw'],
    compatibility: 'compatible',
    packageType: 'bundle',
    packageSkillMdPaths: [],
    updatedAt: 1778664000000,
    status: 'published',
    usage: '',
    originalSkillMd: '',
  );
}

ResponseBody _jsonResponse(
  Map<String, Object?> payload, {
  int statusCode = 200,
}) {
  return ResponseBody.fromString(
    jsonEncode(payload),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }
}
