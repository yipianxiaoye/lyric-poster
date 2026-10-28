import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyric_poster/about_page.dart';
import 'package:lyric_poster/github_profile.dart';

void main() {
  test('公开资料请求使用已确认的作者身份且离线可用', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'api.github.com');
      expect(request.url.path, '/users/yipianxiaoye');
      expect(request.headers.containsKey('Authorization'), isFalse);
      return http.Response(
        jsonEncode({
          'login': 'yipianxiaoye',
          'id': 123964995,
          'html_url': 'https://github.com/yipianxiaoye',
          'avatar_url': 'https://avatars.githubusercontent.com/u/123964995?v=4',
          'name': null,
          'bio': null,
          'location': null,
        }),
        200,
      );
    });
    final author = await loadAuthorProfile(client: client);
    expect(author.displayName, 'yipianxiaoye');
    expect(author.id, 123964995);
    expect(author.bio, isNull);
    client.close();

    final unavailable = MockClient((_) async => http.Response('', 503));
    expect(await loadAuthorProfile(client: unavailable), GitHubProfile.author);
    unavailable.close();
  });

  testWidgets('关于页在手机与桌面显示作者、许可和本机数据说明', (tester) async {
    const profile = GitHubProfile(
      login: 'yipianxiaoye',
      id: 123964995,
      profileUrl: 'https://github.com/yipianxiaoye',
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    for (final width in [320.0, 390.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AboutPage(
              key: ValueKey(width),
              initialProfile: profile,
              profileLoader: () async => profile,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final logo = find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/icons/app_icon.png',
      );
      expect(logo, findsOneWidget);
      await tester.runAsync(() async {
        await precacheImage(
          const AssetImage('assets/icons/app_icon.png'),
          tester.element(logo),
        );
      });
      await tester.pump();
      expect(
        tester
            .widget<RawImage>(
              find.descendant(of: logo, matching: find.byType(RawImage)),
            )
            .image,
        isNotNull,
      );
      expect(find.text('词笺 · Lyric Poster'), findsOneWidget);
      expect(find.text('版本 1.5.3+11'), findsOneWidget);
      expect(find.text('一片小叶'), findsOneWidget);
      expect(find.text('@yipianxiaoye'), findsOneWidget);
      expect(find.text('https://github.com/yipianxiaoye'), findsOneWidget);
      expect(find.text('yipianxiaoye'), findsNothing);
      expect(find.text('本机数据'), findsOneWidget);
      expect(find.textContaining('本机数据不会被上传。'), findsOneWidget);
      expect(find.textContaining('本机记录不会上传到 GitHub'), findsNothing);
      expect(find.textContaining('资料与头像来自作者'), findsNothing);
      expect(find.textContaining('MIT License'), findsOneWidget);
      expect(
        find.textContaining('界面字体：寒蝉全圆体（原生常规字重），SIL Open Font License 1.1'),
        findsOneWidget,
      );
      expect(
        find.textContaining('默认海报字体：Noto Sans SC，SIL Open Font License 1.1'),
        findsOneWidget,
      );
      expect(find.byTooltip('复制作者主页'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
