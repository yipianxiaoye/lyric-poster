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
      final updates = controllerFor(MockClient((_) async => response(data)));
      addTearDown(updates.dispose);
      await updates.check();
      expect(updates.error, isNull);
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

  for (final status in [403, 429]) {
    test('HTTP $status 显示限流提示', () async {
      final updates = controllerFor(
        MockClient((_) async => response({}, status)),
      );
      addTearDown(updates.dispose);
      await updates.check();
      expect(updates.error, contains('过于频繁'));
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
      MockClient((_) async {
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
