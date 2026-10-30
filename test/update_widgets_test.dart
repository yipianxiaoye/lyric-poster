import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyric_poster/app_updates.dart';
import 'package:lyric_poster/update_widgets.dart';

const _repository = 'https://github.com/yipianxiaoye/lyric-poster';

http.Response _releaseResponse(
  String version, {
  String notes = '更新内容',
}) => http.Response.bytes(
  utf8.encode(
    jsonEncode({
      'tag_name': 'v$version',
      'name': '词笺 v$version',
      'html_url': '$_repository/releases/tag/v$version',
      'draft': false,
      'prerelease': false,
      'body': notes,
      'assets': [
        {
          'name': 'LyricPoster-$version-windows-x64.zip',
          'state': 'uploaded',
          'browser_download_url':
              '$_repository/releases/download/v$version/LyricPoster-$version-windows-x64.zip',
        },
      ],
    }),
  ),
  200,
);

UpdateController _controller(http.Client client) => UpdateController(
  client: client,
  versionLoader: () async =>
      const InstalledVersion(version: '1.5.4', buildNumber: '12'),
  platform: TargetPlatform.windows,
);

Widget _panelApp(UpdateController controller, {UpdateUrlLauncher? launcher}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: UpdatePanel(controller: controller, launcher: launcher),
        ),
      ),
    );

ReleaseInfo _release({String? notes}) => ReleaseInfo(
  version: '1.6.0',
  tagName: 'v1.6.0',
  title: '词笺 v1.6.0',
  notes: notes ?? '新增检查更新功能',
  pageUrl: Uri.parse('$_repository/releases/tag/v1.6.0'),
  downloadUrl: Uri.parse(
    '$_repository/releases/download/v1.6.0/LyricPoster-1.6.0-windows-x64.zip',
  ),
);

void main() {
  testWidgets('手动检查期间禁用按钮，检查完成后显示最新状态', (tester) async {
    final pending = Completer<http.Response>();
    var requests = 0;
    final client = MockClient((_) {
      requests++;
      return pending.future;
    });
    final updates = _controller(client);
    addTearDown(updates.dispose);
    addTearDown(client.close);
    await tester.pumpWidget(_panelApp(updates));

    await tester.tap(find.text('检查更新'));
    await tester.pump();
    expect(requests, 1);
    expect(find.text('正在检查更新…'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );

    pending.complete(_releaseResponse('1.5.4'));
    await tester.pumpAndSettle();
    expect(find.text('当前已是最新版本'), findsOneWidget);
    expect(find.textContaining('上次检查：'), findsOneWidget);
    expect(find.text('下载新版'), findsNothing);
    expect(find.text('前往下载页'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('关于页更新卡在窄屏显示新版，并打开对应下载与发布说明', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = MockClient((_) async => _releaseResponse('1.6.0'));
    final updates = _controller(client);
    addTearDown(updates.dispose);
    addTearDown(client.close);
    final opened = <Uri>[];
    await tester.pumpWidget(
      _panelApp(
        updates,
        launcher: (url) async {
          opened.add(url);
          return true;
        },
      ),
    );
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 1.6.0'), findsOneWidget);
    expect(find.text('更新内容'), findsOneWidget);
    await tester.ensureVisible(find.text('下载新版'));
    await tester.tap(find.text('下载新版'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('查看发布说明'));
    await tester.tap(find.text('查看发布说明'));
    await tester.pumpAndSettle();
    expect(opened.first.path, endsWith('LyricPoster-1.6.0-windows-x64.zip'));
    expect(opened.last.path, '/yipianxiaoye/lyric-poster/releases/tag/v1.6.0');
    expect(tester.takeException(), isNull);
  });

  testWidgets('检查失败仍可打开下载页，重试成功后清除错误入口', (tester) async {
    var requests = 0;
    var recovered = false;
    final client = MockClient((_) async {
      requests++;
      return recovered
          ? _releaseResponse('1.5.4')
          : http.Response('Unavailable', 503);
    });
    final updates = _controller(client);
    addTearDown(updates.dispose);
    addTearDown(client.close);
    Uri? opened;
    await tester.pumpWidget(
      _panelApp(
        updates,
        launcher: (url) async {
          opened = url;
          return true;
        },
      ),
    );
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(updates.error, isNotNull);
    expect(find.text(updates.error!), findsOneWidget);
    expect(find.text('重新检查'), findsOneWidget);
    expect(find.text('前往下载页'), findsOneWidget);
    await tester.tap(find.text('前往下载页'));
    await tester.pumpAndSettle();
    expect(opened, Uri.parse('$_repository/releases/latest'));
    recovered = true;
    await tester.tap(find.text('重新检查'));
    await tester.pumpAndSettle();
    expect(requests, greaterThanOrEqualTo(2));
    expect(updates.error, isNull);
    expect(find.text('当前已是最新版本'), findsOneWidget);
    expect(find.text('前往下载页'), findsNothing);
  });

  testWidgets('通过公开发布页检查到新版时，下载按钮打开该版本页面', (tester) async {
    final client = MockClient((request) async {
      if (request.url.host == 'api.github.com') {
        return http.Response('API rate limit exceeded', 403);
      }
      return http.Response(
        '',
        302,
        headers: {'location': '$_repository/releases/tag/v1.6.0'},
      );
    });
    final updates = _controller(client);
    addTearDown(updates.dispose);
    addTearDown(client.close);
    Uri? opened;
    await tester.pumpWidget(
      _panelApp(
        updates,
        launcher: (url) async {
          opened = url;
          return true;
        },
      ),
    );
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 1.6.0'), findsOneWidget);
    expect(find.text('前往下载页'), findsNothing);
    await tester.tap(find.text('下载新版'));
    await tester.pumpAndSettle();
    expect(opened, Uri.parse('$_repository/releases/tag/v1.6.0'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('启动更新提示支持长说明、窄屏下载与稍后关闭', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final release = _release(notes: List.filled(80, '这是一项更新内容。').join('\n'));
    Uri? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppUpdateDialog(
                context,
                release,
                launcher: (url) async {
                  opened = url;
                  return true;
                },
              ),
              child: const Text('提示更新'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('提示更新'));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 1.6.0'), findsOneWidget);
    await tester.tap(find.text('下载新版'));
    await tester.pumpAndSettle();
    expect(opened, release.downloadUrl);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无法打开浏览器时提供可选择和复制的下载链接', (tester) async {
    final release = _release();
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openUpdateUrl(
                context,
                release.downloadUrl!,
                launcher: (_) async => false,
              ),
              child: const Text('下载'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();
    expect(find.text('无法打开浏览器'), findsOneWidget);
    expect(find.text(release.downloadUrl.toString()), findsOneWidget);
    await tester.tap(find.text('复制链接'));
    await tester.pumpAndSettle();
    expect(copied, release.downloadUrl.toString());
    expect(tester.takeException(), isNull);
  });
}
