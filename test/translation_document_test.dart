import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_poster/font_library.dart';
import 'package:lyric_poster/netease_client.dart';
import 'package:lyric_poster/poster_document.dart';
import 'package:lyric_poster/poster_renderer.dart';

PosterDocument document({
  String lyrics = 'The light is still here\nWe will meet again',
  String translation = '光仍在这里\n我们会再次相见',
  bool showTranslation = true,
  double translationSize = 14,
  String dimensions = 'A5 竖版',
  int maxLines = 24,
}) => PosterDocument(
  track: Track(
    id: '',
    title: 'A little light',
    artist: '歌手',
    album: '专辑',
    coverUrl: '',
    lyrics: lyrics,
    translation: translation,
  ),
  layout: '居中',
  dimensions: dimensions,
  titleSize: 26,
  lyricSize: 18,
  showTranslation: showTranslation,
  translationSize: translationSize,
  translationFontFamily: 'TranslationFont',
  background: Colors.white,
  accent: Colors.indigo,
  overlay: 0,
  maxLinesPerPage: maxLines,
);

Iterable<TextSpan> children(PosterDocument doc, int page) =>
    doc.pageTextSpan(page).children?.cast<TextSpan>() ?? const [];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final font = await rootBundle.load('assets/fonts/NotoSansSC.ttf');
    await (FontLoader(defaultFontFamily)..addFont(Future.value(font))).load();
    final translatedFont = await rootBundle.load(
      'assets/fonts/ChillRoundF.ttf',
    );
    await (FontLoader(
      'TranslationFont',
    )..addFont(Future.value(translatedFont))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  test('译文逐句跟随原文，并使用独立字体和打印字号', () {
    final doc = document(translationSize: 12.5);
    expect(doc.pages.join(), doc.lyrics);
    expect(
      doc.pageTextSpan(0).toPlainText(),
      'The light is still here\n光仍在这里\nWe will meet again\n我们会再次相见',
    );
    final spans = children(
      doc,
      0,
    ).where((span) => span.style?.fontFamily == 'TranslationFont');
    expect(spans.map((span) => span.text), ['光仍在这里', '我们会再次相见']);
    expect(spans.every((span) => span.style?.fontSize == 12.5), isTrue);
    expect(doc.lyricStyle.fontFamily, defaultFontFamily);
    expect(doc.lyricStyle.fontSize, 18);
  });

  test('关闭译文或无译文时完全保留原有排版，无占位空行', () {
    final hidden = document(showTranslation: false);
    final unavailable = document(translation: '');
    expect(hidden.hasTranslation, isFalse);
    expect(unavailable.hasTranslation, isFalse);
    expect(hidden.pages, unavailable.pages);
    expect(hidden.pageTextSpan(0).toPlainText(), hidden.lyrics);
    final partial = document(translation: '\n我们会再次相见');
    expect(
      partial.pageTextSpan(0).toPlainText(),
      'The light is still here\nWe will meet again\n我们会再次相见',
    );
  });

  test('原文首尾空行被裁掉时译文仍对应正确位置', () {
    final doc = document(
      lyrics: '\n  \nThe first line\n\nThe last line\n',
      translation: '\n\n第一句\n\n最后一句\n',
    );
    expect(
      doc.pageTextSpan(0).toPlainText(),
      'The first line\n第一句\n\nThe last line\n最后一句',
    );
    expect(doc.pages.join(), doc.lyrics);
  });

  test('每页行数按原文计算，短原文和译文保持同页', () {
    final original = List.generate(20, (i) => 'Line ${i + 1}');
    final translated = List.generate(20, (i) => '译文${i + 1}');
    final doc = document(
      lyrics: original.join('\n'),
      translation: translated.join('\n'),
      dimensions: 'A3 竖版',
      maxLines: 8,
    );
    expect(doc.pages, hasLength(3));
    expect(doc.pages.join(), doc.lyrics);
    for (var i = 0; i < original.length; i++) {
      final page = doc.pages.indexWhere(
        (text) => text.split('\n').contains(original[i]),
      );
      expect(page, greaterThanOrEqualTo(0));
      expect(
        doc.pageTextSpan(page).toPlainText(),
        contains('${original[i]}\n${translated[i]}'),
      );
    }
  });

  test('所有纸张的混合字号双语分页均不越界且不丢原文译文', () {
    final original = List.generate(
      32,
      (i) => 'Line ${i + 1}: the morning light is here',
    );
    final translated = List.generate(32, (i) => '第${i + 1}句：晨光依旧照耀着这里');
    for (final dimensions in ['A6 竖版', 'A5 横版', 'A4 竖版', 'A3 横版', '16:9 横版']) {
      final doc = document(
        lyrics: original.join('\n'),
        translation: translated.join('\n'),
        dimensions: dimensions,
        translationSize: 22,
      );
      expect(doc.pages.join(), doc.lyrics, reason: dimensions);
      final exportedTranslations = <String>[];
      for (var page = 0; page < doc.pages.length; page++) {
        expect(
          doc.textHeightForPage(page),
          lessThanOrEqualTo(doc.lyricHeightForPage(page)),
          reason: '$dimensions, page $page',
        );
        exportedTranslations.addAll(
          children(doc, page)
              .where((span) => span.style?.fontFamily == 'TranslationFont')
              .map((span) => span.text ?? ''),
        );
      }
      expect(
        exportedTranslations.join(),
        translated.join(),
        reason: dimensions,
      );
    }
  });

  test('极长原文和译文可分多页，完整保留 Unicode 字符', () {
    final original = '星光🎵' * 450;
    final translated = '明日🌙' * 600;
    final doc = document(
      lyrics: original,
      translation: translated,
      dimensions: 'A6 竖版',
      translationSize: 26,
    );
    expect(doc.pages.length, greaterThan(3));
    expect(doc.pages.join(), original);
    expect(
      [
        for (var page = 0; page < doc.pages.length; page++)
          ...children(doc, page)
              .where((span) => span.style?.fontFamily == 'TranslationFont')
              .map((span) => span.text ?? ''),
      ].join(),
      translated,
    );
    for (var page = 0; page < doc.pages.length; page++) {
      expect(
        doc.textHeightForPage(page),
        lessThanOrEqualTo(doc.lyricHeightForPage(page)),
      );
      expect(
        doc.pageTextSpan(page).toPlainText().runes,
        isNot(contains(0xfffd)),
      );
    }
  });

  testWidgets('预览与独立导出渲染同一双语文本和样式', (tester) async {
    final doc = document();
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: PosterPage(document: doc, page: 0),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final text = tester.widget<Text>(
      find.byKey(const ValueKey('poster-lyrics')),
    );
    expect(text.textSpan!.toPlainText(), contains('光仍在这里'));
    await tester.runAsync(() async {
      final exported = await renderPosterPage(
        doc,
        0,
        context: key.currentContext!,
        dpi: 72,
      );
      final codec = await ui.instantiateImageCodec(exported);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, doc.size.width.ceil());
      expect(frame.image.height, doc.size.height.ceil());
      final preview =
          await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final previewBytes = await preview.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final exportBytes = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(
        exportBytes!.buffer.asUint8List(),
        previewBytes!.buffer.asUint8List(),
      );
      if (const bool.fromEnvironment('WRITE_PREVIEWS')) {
        await Directory('work/previews').create(recursive: true);
        await File('work/previews/bilingual-poster.png').writeAsBytes(exported);
        final previewDocument = document(
          lyrics: [
            for (var index = 0; index < 3; index++) ...[
              'Morning opens a quiet window',
              'Light falls gently on the street',
              'Every step can start a story',
              'Every road can lead us home',
              'Keep a little hope for tomorrow',
            ],
          ].join('\n'),
          translation: [
            for (var index = 0; index < 3; index++) ...[
              '清晨推开一扇安静的窗',
              '光轻轻落在街道上',
              '每一步都能开启一个故事',
              '每条路都能带我们回家',
              '为明天保留一点希望',
            ],
          ].join('\n'),
        );
        for (var page = 0; page < previewDocument.pages.length; page++) {
          final png = await renderPosterPage(
            previewDocument,
            page,
            context: key.currentContext!,
            dpi: 144,
          );
          await File(
            'work/previews/bilingual-poster-${page + 1}.png',
          ).writeAsBytes(png);
        }
      }
      preview.dispose();
      frame.image.dispose();
      codec.dispose();
    });
    expect(tester.takeException(), isNull);
  });
}
