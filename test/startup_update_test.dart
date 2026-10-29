import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyric_poster/app_updates.dart';
import 'package:lyric_poster/main.dart';

void main() {
  http.Response releaseResponse(String version) => http.Response(
    jsonEncode({
      'tag_name': 'v$version',
      'name': '词笺 v$version',
      'body': '改进了歌词排版。',
      'draft': false,
      'prerelease': false,
      'html_url':
          'https://github.com/yipianxiaoye/lyric-poster/releases/tag/v$version',
      'assets': <Object>[],
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  UpdateController updater(http.Client client) => UpdateController(
    client: client,
    versionLoader: () async =>
        const InstalledVersion(version: '1.5.4', buildNumber: '12'),
  );

  testWidgets('启动检查一次，新版提示关闭后切换页面不再弹出', (tester) async {
    var requests = 0;
    final updates = updater(
      MockClient((_) async {
        requests++;
        return releaseResponse('1.6.0');
      }),
    );
    final controller = PosterController();
    addTearDown(updates.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PosterWorkspace(controller: controller, updates: updates),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.byType(AlertDialog), findsOneWidget);
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();
    controller.setTab(4);
    await tester.pumpAndSettle();
    controller.setTab(0);
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.byType(AlertDialog), findsNothing);

    // A fresh workspace represents the next app launch and checks again.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        home: PosterWorkspace(controller: controller, updates: updates),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final version in ['1.5.4', '1.5.3']) {
    testWidgets('本机版本不低于 $version 时启动保持安静', (tester) async {
      final updates = updater(
        MockClient((_) async => releaseResponse(version)),
      );
      final controller = PosterController();
      addTearDown(updates.dispose);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: PosterWorkspace(controller: controller, updates: updates),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('导入网易云歌单'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('启动联网失败不弹窗也不阻止主页使用', (tester) async {
    final updates = updater(
      MockClient((_) async => throw http.ClientException('offline')),
    );
    final controller = PosterController();
    addTearDown(updates.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PosterWorkspace(controller: controller, updates: updates),
      ),
    );
    await tester.pumpAndSettle();
    expect(updates.error, isNotNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('开始导入'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('退出页面后到达的新版响应不打开提示', (tester) async {
    final response = Completer<http.Response>();
    final updates = updater(MockClient((_) => response.future));
    final controller = PosterController();
    addTearDown(updates.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PosterWorkspace(controller: controller, updates: updates),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    response.complete(releaseResponse('1.6.0'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
