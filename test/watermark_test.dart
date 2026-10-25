import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_poster/font_library.dart';
import 'package:lyric_poster/netease_client.dart';
import 'package:lyric_poster/poster_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final font = FontLoader(defaultFontFamily)
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'));
    await font.load();
  });

  PosterDocument document({
    String? top,
    String bottom = '词笺 · LYRIC POSTER',
    bool showTop = true,
    bool showBottom = true,
    bool decoration = true,
  }) => PosterDocument(
    track: Track(
      id: '',
      title: '歌词海报',
      artist: '歌手',
      album: '自选专辑',
      coverUrl: '',
      lyrics: List.generate(25, (i) => '第 ${i + 1} 句歌词').join('\n'),
    ),
    layout: '居中',
    dimensions: 'A6 竖版',
    titleSize: 30,
    lyricSize: 15,
    background: Colors.white,
    accent: Colors.deepPurple,
    overlay: .46,
    topWatermark: top,
    bottomWatermark: bottom,
    showTopWatermark: showTop,
    showBottomWatermark: showBottom,
    showTopDecoration: decoration,
  );

  Future<void> showPage(
    WidgetTester tester,
    PosterDocument doc,
    int page, {
    ValueChanged<PosterElement>? onTap,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: FittedBox(
            child: PosterPage(document: doc, page: page, onElementTap: onTap),
          ),
        ),
      ),
    ),
  );

  testWidgets('上下水印默认兼容旧海报，顶部只显示首页', (tester) async {
    final doc = document();
    await showPage(tester, doc, 0);
    expect(find.text('LYRIC / 自选专辑'), findsOneWidget);
    expect(find.text('词笺 · LYRIC POSTER'), findsOneWidget);
    expect(find.byKey(const ValueKey('poster-top-decoration')), findsOneWidget);
    await showPage(tester, doc, 1);
    expect(find.byKey(const ValueKey('poster-top-watermark')), findsNothing);
    expect(find.byKey(const ValueKey('poster-top-decoration')), findsNothing);
    expect(find.text('词笺 · LYRIC POSTER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自定义水印可点击编辑，长文本不会挤出页码', (tester) async {
    final customTop = '音乐手记 ' * 30;
    final customBottom = '私人收藏 · 自定义歌词海报 ' * 30;
    final taps = <PosterElement>[];
    await showPage(
      tester,
      document(top: customTop, bottom: customBottom),
      0,
      onTap: taps.add,
    );
    final top = find.byKey(const ValueKey('poster-top-watermark'));
    final bottom = find.byKey(const ValueKey('poster-bottom-watermark'));
    expect(tester.widget<Text>(top).data, customTop);
    expect(tester.widget<Text>(bottom).data, customBottom);
    await tester.tap(top);
    await tester.tap(bottom);
    expect(taps, [PosterElement.topWatermark, PosterElement.bottomWatermark]);
    expect(find.text('1 / ${document().pages.length}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('水印可独立隐藏，留空也不显示默认文字', (tester) async {
    await showPage(
      tester,
      document(showTop: false, showBottom: false, decoration: false),
      0,
    );
    expect(find.byKey(const ValueKey('poster-top-watermark')), findsNothing);
    expect(find.byKey(const ValueKey('poster-bottom-watermark')), findsNothing);
    expect(find.byKey(const ValueKey('poster-top-decoration')), findsNothing);
    await showPage(tester, document(top: '', bottom: '', decoration: false), 0);
    expect(find.byKey(const ValueKey('poster-top-watermark')), findsNothing);
    expect(find.byKey(const ValueKey('poster-bottom-watermark')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
