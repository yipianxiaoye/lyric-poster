import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:lyric_poster/main.dart';
import 'package:lyric_poster/poster_document.dart';
import 'package:lyric_poster/app_updates.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('网易云歌单链接可以提取歌单 ID', () {
    final client = NeteaseClient();
    addTearDown(client.close);
    expect(
      client.parsePlaylistId('https://music.163.com/playlist?id=123456789'),
      '123456789',
    );
    expect(client.parsePlaylistId('123456789'), '123456789');
    expect(client.parsePlaylistId('这不是歌单'), isNull);
  });

  testWidgets('首页显示歌单导入入口', (tester) async {
    final updates = UpdateController(
      client: MockClient((_) async => http.Response('', 404)),
      versionLoader: () async =>
          const InstalledVersion(version: '1.5.4', buildNumber: '12'),
    );
    addTearDown(updates.dispose);
    await tester.pumpWidget(LyricPosterApp(updates: updates));
    final logo = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName == 'assets/icons/app_icon.png',
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
    expect(find.text('导入网易云歌单'), findsOneWidget);
    expect(find.text('开始导入'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  test('长歌词可调整每页行数，预览不会只保留前九行', () async {
    final controller = PosterController();
    final track = Track(
      id: '',
      title: '测试',
      artist: '歌手',
      album: '专辑',
      coverUrl: '',
      lyrics: List.generate(25, (index) => '第 ${index + 1} 行').join('\n'),
    );
    controller.selected = track;
    expect(controller.maxLinesPerPage, PosterController.defaultMaxLinesPerPage);
    await controller.setMaxLinesPerPage(12);
    expect(controller.lyricPageCount, 3);
    expect(controller.currentLyricPageLines, hasLength(12));
    controller.setLyricPage(2);
    expect(controller.currentLyricPageLines, ['第 25 行']);
    await controller.setMaxLinesPerPage(24);
    expect(controller.lyricPageCount, 2);
    controller.dispose();
  });

  test('海报文档将完整歌词生成对应页数', () {
    final document = PosterDocument(
      track: Track(
        id: '',
        title: '测试',
        artist: '歌手',
        album: '专辑',
        coverUrl: '',
        lyrics: List.generate(25, (index) => '第 ${index + 1} 行').join('\n'),
      ),
      layout: '居中',
      dimensions: 'A4 竖版',
      titleSize: 30,
      lyricSize: 15,
      background: const Color(0xFF17151F),
      accent: const Color(0xFFC9B8FF),
      overlay: .46,
      maxLinesPerPage: 12,
    );
    expect(document.pages, hasLength(3));
    expect(document.pages.first, startsWith('第 1 行'));
    expect(document.pages.last, '第 25 行');
  });
}
