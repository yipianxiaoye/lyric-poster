import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyric_poster/app_updates.dart';
import 'package:package_info_plus/package_info_plus.dart';

Map<String, Object?> release({
  String tag = 'v1.5.4',
  bool draft = false,
  bool prerelease = false,
  List<Map<String, Object?>>? assets,
}) => {
  'tag_name': tag,
  'name': '词笺 $tag',
  'body': '新增检查更新\n修复字体显示',
  'draft': draft,
  'prerelease': prerelease,
  'html_url': 'https://github.com/yipianxiaoye/lyric-poster/releases/tag/$tag',
  'assets': assets ?? [],
};

Map<String, Object?> asset(String name, {String tag = 'v1.5.4'}) => {
  'name': name,
  'state': 'uploaded',
  'browser_download_url':
      'https://github.com/yipianxiaoye/lyric-poster/releases/download/$tag/$name',
};

http.Response response(Object? data, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(data)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.Response redirect({
  int status = 302,
  String location =
      'https://github.com/yipianxiaoye/lyric-poster/releases/tag/v1.5.4',
}) => http.Response('', status, headers: {'location': location});

UpdateController controllerFor(
  http.Client client, {
  String version = '1.5.3',
  String buildNumber = '11',
  TargetPlatform platform = TargetPlatform.windows,
  Duration timeout = const Duration(seconds: 1),
}) => UpdateController(
  client: client,
  versionLoader: () async =>
      InstalledVersion(version: version, buildNumber: buildNumber),
  platform: platform,
  timeout: timeout,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('安装版本从实际包信息读取，保留构建号', () async {
    PackageInfo.setMockInitialValues(
      appName: '词笺',
      packageName: 'com.example.lyric_poster',
      version: '1.5.4',
      buildNumber: '12',
      buildSignature: '',
    );
    final version = await InstalledVersion.load();
    expect(version.version, '1.5.4');
    expect(version.display, '1.5.4+12');
    expect(
      const InstalledVersion(version: '1.5.4', buildNumber: '').display,
      '1.5.4',
    );
  });

  test('仅加载版本时不联网，正式版本请求不携带认证或本机数据', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(
        request.url.toString(),
        'https://api.github.com/repos/yipianxiaoye/lyric-poster/releases/latest',
      );
      expect(request.method, 'GET');
      expect(request.url.query, isEmpty);
      expect(request.headers['Authorization'], isNull);
      expect(request.headers['Accept'], 'application/vnd.github+json');
      expect(request.headers['User-Agent'], 'LyricPoster/1.5.3');
      return response(release());
    });
    final updates = controllerFor(client);
    addTearDown(updates.dispose);
    await updates.loadInstalledVersion();
    expect(updates.installedVersion!.display, '1.5.3+11');
    expect(requests, 0);
    await updates.check();
    expect(requests, 1);
    expect(updates.error, isNull);
    expect(updates.updateAvailable, isTrue);
    expect(updates.latestRelease!.title, '词笺 v1.5.4');
    expect(updates.latestRelease!.notes, '新增检查更新\n修复字体显示');
    expect(updates.lastCheckedAt, isNotNull);
  });

  for (final comparison in [
    ('1.9.0', 'v1.10.0', true),
    ('1.5.4', 'v1.5.4', false),
    ('1.5.5', 'v1.5.4', false),
    ('1.5.4+12', 'v1.5.4+99', false),
    ('1.5.4-rc.1', 'v1.5.4', true),
    ('2.0.0', 'v1.99.99', false),
  ]) {
    test('按版本号比较 ${comparison.$1} 与 ${comparison.$2}', () async {
      final updates = controllerFor(
        MockClient((_) async => response(release(tag: comparison.$2))),
        version: comparison.$1,
      );
      addTearDown(updates.dispose);
      await updates.check();
      expect(updates.error, isNull);
      expect(updates.updateAvailable, comparison.$3);
    });
  }

  for (final data in [
    release(draft: true),
    release(prerelease: true),
    release(tag: 'v2.0.0-beta.1'),
  ]) {
    test('草稿与预发布版本不会触发正式更新 ${data['tag_name']}', () async {
      final updates = controllerFor(
        MockClient(
          (request) async => request.url.host == 'api.github.com'
              ? response(data)
              : response({}, 404),
        ),
      );
      addTearDown(updates.dispose);
      await updates.check();
      expect(updates.error, contains('没有可用的正式版本'));
      expect(updates.latestRelease, isNull);
      expect(updates.updateAvailable, isFalse);
    });
  }

  for (final entry in [
    (TargetPlatform.windows, 'LyricPoster-1.5.4-windows-x64.zip'),
    (TargetPlatform.android, 'LyricPoster-1.5.4-android-universal.apk'),
  ]) {
    test('选择平台对应的正式安装包 ${entry.$1}', () async {
      final updates = controllerFor(
        MockClient(
          (_) async => response(
            release(
              assets: [
                asset('LyricPoster-1.5.4-windows-x64.zip'),
                asset('LyricPoster-1.5.4-android-universal.apk'),
                asset('SHA256SUMS.txt'),
              ],
            ),
          ),
        ),
        platform: entry.$1,
      );
      addTearDown(updates.dispose);
      await updates.check();
      expect(updates.latestRelease!.downloadUrl!.pathSegments.last, entry.$2);
    });
  }

  test('没有本平台安装包时保留发布页，拒绝跳到其他站点下载', () async {
    final updates = controllerFor(
      MockClient(
        (_) async => response(
          release(
            assets: [
              {
                ...asset('LyricPoster-1.5.4-windows-x64.zip'),
                'browser_download_url': 'https://example.com/untrusted.zip',
              },
            ],
          ),
        ),
      ),
    );
    addTearDown(updates.dispose);
    await updates.check();
    expect(updates.updateAvailable, isTrue);
    expect(updates.latestRelease!.downloadUrl, isNull);
    expect(
      updates.latestRelease!.pageUrl.toString(),
      'https://github.com/yipianxiaoye/lyric-poster/releases/tag/v1.5.4',
    );
  });

  for (final badData in [
    'not a release',
    release(tag: 'latest'),
    {...release(), 'draft': null},
    {...release(), 'assets': null},
    {...release(), 'html_url': 'https://example.com/releases/tag/v1.5.4'},
    {
      ...release(),
      'html_url':
          'https://github.com/another-user/lyric-poster/releases/tag/v1.5.4',
    },
    {
      ...release(),
      'html_url':
          'http://github.com/yipianxiaoye/lyric-poster/releases/tag/v1.5.4',
    },
  ]) {
    test('无效发布信息不会提供更新链接 ${badData.runtimeType}', () async {
      final updates = controllerFor(MockClient((_) async => response(badData)));
      addTearDown(updates.dispose);
      await updates.check();
      expect(updates.error, contains('无法识别'));
      expect(updates.updateAvailable, isFalse);
    });
  }

  for (final entry in [
    (403, {'x-ratelimit-remaining': '0'}, true),
    (429, <String, String>{}, true),
    (403, {'x-ratelimit-remaining': '59'}, false),
  ]) {
    test('HTTP ${entry.$1} 依据实际额度说明服务状态 ${entry.$2}', () async {
      final updates = controllerFor(
        MockClient((_) async => http.Response('', entry.$1, headers: entry.$2)),
      );
      addTearDown(updates.dispose);
      await updates.check();
      expect(updates.error, isNot(contains('过于频繁')));
      expect(updates.error, isNot(contains('你')));
      expect(
        updates.error,
        entry.$3 ? contains('请求额度暂时用尽') : contains('HTTP 403'),
      );
      expect(updates.checking, isFalse);
    });
  }

  test('没有正式版本时显示明确提示', () async {
    final updates = controllerFor(MockClient((_) async => response({}, 404)));
    addTearDown(updates.dispose);
    await updates.check();
    expect(updates.error, contains('没有可用的正式版本'));
    expect(updates.updateAvailable, isFalse);
  });

  test('网络异常与超时不会抛出异常或留下加载状态', () async {
    for (final client in [
      MockClient((_) async => throw http.ClientException('offline')),
      MockClient((_) => Completer<http.Response>().future),
    ]) {
      final updates = controllerFor(
        client,
        timeout: const Duration(milliseconds: 5),
      );
      await updates.check();
      expect(updates.error, contains('网络'));
      expect(updates.checking, isFalse);
      expect(updates.updateAvailable, isFalse);
      updates.dispose();
    }
  });

  test('同时检查共用请求，完成后允许再次手动检查', () async {
    final result = Completer<http.Response>();
    var requests = 0;
    final updates = controllerFor(
      MockClient((_) {
        requests++;
        return result.future;
      }),
    );
    addTearDown(updates.dispose);
    final startup = updates.check();
    final manual = updates.check();
    expect(identical(startup, manual), isTrue);
    expect(updates.checking, isTrue);
    expect(updates.updateAvailable, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1);
    result.complete(response(release()));
    await Future.wait([startup, manual]);
    expect(updates.updateAvailable, isTrue);
    await updates.check();
    expect(requests, 2);
  });

  test('已知更新后网络失败不会重复弹出过时结果，随后可重试', () async {
    var requests = 0;
    final updates = controllerFor(
      MockClient((request) async {
        if (request.url.host == 'github.com') return response({}, 503);
        requests++;
        return requests == 2 ? response({}, 503) : response(release());
      }),
    );
    addTearDown(updates.dispose);
    await updates.check();
    expect(updates.updateAvailable, isTrue);
    final firstCheck = updates.lastCheckedAt;
    await updates.check();
    expect(updates.error, contains('503'));
    expect(updates.latestRelease, isNotNull);
    expect(updates.updateAvailable, isFalse);
    expect(updates.lastCheckedAt, firstCheck);
    await updates.check();
    expect(updates.error, isNull);
    expect(updates.updateAvailable, isTrue);
  });

  test('退出应用后完成的请求不会再通知界面，也不关闭外部客户端', () async {
    final result = Completer<http.Response>();
    final client = TrackingClient((_) => result.future);
    final updates = controllerFor(client);
    var notifications = 0;
    updates.addListener(() => notifications++);
    final checking = updates.check();
    await Future<void>.delayed(Duration.zero);
    updates.dispose();
    final notificationsAtDispose = notifications;
    result.complete(response(release()));
    await checking;
    expect(notifications, notificationsAtDispose);
    expect(client.closed, isFalse);
    await updates.check();
    expect(notifications, notificationsAtDispose);
    client.close();
  });

  for (final apiFailure in [
    'quota',
    'forbidden',
    '429',
    'network',
    'timeout',
    '503',
    '404',
    'malformed',
  ]) {
    test('接口 $apiFailure 时通过官方发布页跳转确认新版本', () async {
      var apiRequests = 0;
      var webRequests = 0;
      final updates = controllerFor(
        MockClient((request) async {
          expect(request.headers['Authorization'], isNull);
          if (request.url.host == 'api.github.com') {
            apiRequests++;
            return switch (apiFailure) {
              'quota' => http.Response(
                '',
                403,
                headers: {'x-ratelimit-remaining': '0'},
              ),
              'forbidden' => response({}, 403),
              '429' => response({}, 429),
              'network' => throw http.ClientException('offline'),
              'timeout' => Completer<http.Response>().future,
              '503' => response({}, 503),
              '404' => response({}, 404),
              _ => response({'message': 'unexpected metadata'}),
            };
          }
          webRequests++;
          expect(request.method, 'GET');
          expect(
            request.url.toString(),
            'https://github.com/yipianxiaoye/lyric-poster/releases/latest',
          );
          expect(request.followRedirects, isFalse);
          expect(request.headers['Accept'], 'text/html');
          return redirect();
        }),
        timeout: const Duration(milliseconds: 20),
      );
      addTearDown(updates.dispose);
      await updates.check();
      expect(apiRequests, 1);
      expect(webRequests, 1);
      expect(updates.error, isNull);
      expect(updates.updateAvailable, isTrue);
      expect(updates.latestRelease!.version, '1.5.4');
      expect(updates.latestRelease!.title, '词笺 v1.5.4');
      expect(updates.latestRelease!.notes, isEmpty);
      expect(updates.latestRelease!.downloadUrl, isNull);
      expect(
        updates.latestRelease!.pageUrl.toString(),
        'https://github.com/yipianxiaoye/lyric-poster/releases/tag/v1.5.4',
      );
      expect(updates.lastCheckedAt, isNotNull);
    });
  }

  for (final status in [301, 302, 303, 307, 308]) {
    test('接受官方发布页的相对稳定版本跳转 HTTP $status', () async {
      final updates = controllerFor(
        MockClient(
          (request) async => request.url.host == 'api.github.com'
              ? response({}, 503)
              : redirect(
                  status: status,
                  location: '/yipianxiaoye/lyric-poster/releases/tag/v1.5.4',
                ),
        ),
      );
      addTearDown(updates.dispose);
      await updates.check();
      expect(updates.error, isNull);
      expect(updates.updateAvailable, isTrue);
    });
  }

  for (final location in [
    'https://example.com/yipianxiaoye/lyric-poster/releases/tag/v9.0.0',
    'https://github.com/another-user/lyric-poster/releases/tag/v9.0.0',
    'http://github.com/yipianxiaoye/lyric-poster/releases/tag/v9.0.0',
    '/yipianxiaoye/lyric-poster/releases/tag/v9.0.0-beta.1',
    '/yipianxiaoye/lyric-poster/releases/tag/untagged-draft',
    '/yipianxiaoye/lyric-poster/releases/tag/latest',
    '/yipianxiaoye/lyric-poster/releases/latest',
    '/yipianxiaoye/lyric-poster/releases/tag/v9.0.0?redirect=example.com',
    '',
  ]) {
    test('不接受不可信或非正式版本的发布页跳转 $location', () async {
      final updates = controllerFor(
        MockClient(
          (request) async => request.url.host == 'api.github.com'
              ? response({}, 503)
              : redirect(location: location),
        ),
      );
      addTearDown(updates.dispose);
      await updates.check();
      expect(updates.error, isNotNull);
      expect(updates.latestRelease, isNull);
      expect(updates.lastCheckedAt, isNull);
      expect(updates.updateAvailable, isFalse);
    });
  }

  test('HTTP200 的通用网页和没有 Location 的跳转都不等于检查成功', () async {
    for (final webResponse in [
      http.Response('<html>GitHub unavailable</html>', 200),
      http.Response('', 302),
    ]) {
      final updates = controllerFor(
        MockClient(
          (request) async => request.url.host == 'api.github.com'
              ? response({}, 503)
              : webResponse,
        ),
      );
      await updates.check();
      expect(updates.error, isNotNull);
      expect(updates.latestRelease, isNull);
      expect(updates.updateAvailable, isFalse);
      updates.dispose();
    }
  });

  test('发布页响应体不结束时也受超时约束', () async {
    final body = StreamController<List<int>>();
    final updates = controllerFor(
      MockClient.streaming((request, _) async {
        if (request.url.host == 'api.github.com') {
          return http.StreamedResponse(Stream.value([]), 503);
        }
        return http.StreamedResponse(
          body.stream,
          302,
          headers: {
            'location': '/yipianxiaoye/lyric-poster/releases/tag/v1.5.4',
          },
        );
      }),
      timeout: const Duration(milliseconds: 10),
    );
    addTearDown(updates.dispose);
    await updates.check().timeout(const Duration(seconds: 1));
    expect(updates.checking, isFalse);
    expect(updates.error, isNotNull);
    expect(updates.updateAvailable, isFalse);
    await body.close();
  });

  test('备用检查同样合并并发请求，手动重试会重新访问官方来源', () async {
    final webResult = Completer<http.Response>();
    var apiRequests = 0;
    var webRequests = 0;
    final updates = controllerFor(
      MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          apiRequests++;
          return response({}, 429);
        }
        webRequests++;
        return webResult.future;
      }),
    );
    addTearDown(updates.dispose);
    final startup = updates.check();
    await Future<void>.delayed(Duration.zero);
    final manual = updates.check();
    expect(identical(startup, manual), isTrue);
    expect(apiRequests, 1);
    expect(webRequests, 1);
    webResult.complete(redirect());
    await Future.wait([startup, manual]);
    expect(updates.updateAvailable, isTrue);
    await updates.check();
    expect(apiRequests, 2);
    expect(webRequests, 2);
  });

  test('已知更新后两条检查路径均失败时不会继续报告更新成功', () async {
    var checks = 0;
    final updates = controllerFor(
      MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          checks++;
          return checks == 1 ? response(release()) : response({}, 429);
        }
        return response({}, 503);
      }),
    );
    addTearDown(updates.dispose);
    await updates.check();
    final checkedAt = updates.lastCheckedAt;
    expect(updates.updateAvailable, isTrue);
    await updates.check();
    expect(updates.latestRelease, isNotNull);
    expect(updates.lastCheckedAt, checkedAt);
    expect(updates.error, contains('公共更新服务'));
    expect(updates.updateAvailable, isFalse);
  });

  test('退出后主接口失败时不会启动备用检查', () async {
    final apiResult = Completer<http.Response>();
    var webRequests = 0;
    final updates = controllerFor(
      MockClient((request) async {
        if (request.url.host == 'github.com') webRequests++;
        return apiResult.future;
      }),
    );
    final pending = updates.check();
    await Future<void>.delayed(Duration.zero);
    updates.dispose();
    apiResult.complete(response({}, 429));
    await pending;
    expect(webRequests, 0);
  });
}

class TrackingClient extends MockClient {
  TrackingClient(super.fn);

  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }
}
