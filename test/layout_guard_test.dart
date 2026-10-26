import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_poster/editor_fields.dart';
import 'package:lyric_poster/font_library.dart';
import 'package:lyric_poster/main.dart';
import 'package:lyric_poster/poster_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader(defaultFontFamily)
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'));
    await font.load();
  });

  Track track(String title) => Track(
    id: '',
    title: title,
    artist: '歌手',
    album: '测试诗集',
    coverUrl: '',
    lyrics: '自写的测试短句\n留给纸上的微风',
  );

  PosterController smallPoster({String title = '风', double size = 96}) {
    final controller = PosterController()..selected = track(title);
    expect(controller.setDimensions('A6 竖版'), isTrue);
    expect(controller.setTitleSize(size), isTrue);
    return controller;
  }

  testWidgets('小纸高字号拒绝过长标题，输入保留错误而预览仍有效', (tester) async {
    final controller = smallPoster();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => Column(
              children: [
                LiveTextField(
                  label: '歌曲标题',
                  value: controller.selected!.title,
                  onChanged: (text) => controller.updateSelected(title: text),
                ),
                Expanded(
                  child: FittedBox(
                    child: PosterPage(document: controller.document!, page: 0),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final field = find.byType(TextField);
    await tester.enterText(field, '风与远方');
    await tester.pump();
    expect(controller.selected!.title, '风');
    expect(controller.titleSize, 96);
    expect(controller.lyricSize, 15);
    expect(controller.document!.title, '风');
    expect(tester.widget<TextField>(field).controller!.text, '风与远方');
    expect(tester.widget<TextField>(field).decoration!.errorText, isNotNull);
    expect(find.text('风'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(field, '雨');
    await tester.pump();
    expect(controller.selected!.title, '雨');
    expect(tester.widget<TextField>(field).decoration!.errorText, isNull);
    expect(tester.takeException(), isNull);
  });

  test('小纸高字号换版式失败回滚，换纸和字号也保留可打印状态', () {
    final controller = smallPoster(title: '春风', size: 116);
    addTearDown(controller.dispose);
    expect(controller.setLayout('左对齐'), isFalse);
    expect(controller.layout, '居中');
    expect(controller.titleSize, 116);
    expect(controller.document!.title, '春风');
    expect(controller.setTitleSize(144), isFalse);
    expect(controller.titleSize, 116);
    expect(controller.setLyricSize(96), isFalse);
    expect(controller.lyricSize, 15);
    expect(controller.setDimensions('invalid-paper'), isFalse);
    expect(controller.dimensions, 'A6 竖版');
    expect(controller.document!.pages, isNotEmpty);
  });

  test('小纸高字号切歌及新建失败保留原歌和字号，并说明失败原因', () async {
    final controller = smallPoster();
    addTearDown(controller.dispose);
    final original = controller.selected!;
    final longer = track('风与远方');
    controller.tracks.addAll([original, longer]);
    await controller.selectTrack(longer, fetchLyrics: false);
    expect(controller.selected, same(original));
    expect(controller.historyError, isNotEmpty);
    expect(controller.document!.title, '风');
    expect(controller.titleSize, 96);
    expect(controller.lyricSize, 15);
    final before = List<Track>.of(controller.tracks);
    await controller.addManualTrack();
    expect(controller.selected, same(original));
    expect(controller.tracks, before);
    expect(controller.historyError, isNotEmpty);
    expect(controller.titleSize, 96);
    expect(controller.lyricSize, 15);
    expect(controller.document!.pages, isNotEmpty);
  });
}
