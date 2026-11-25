import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_poster/history_storage.dart';
import 'package:lyric_poster/history_store.dart';
import 'package:lyric_poster/main.dart';
import 'package:lyric_poster/poster_document.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryStorage implements HistoryStorage {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);
}

Track _track({String lyrics = 'A line of lyrics', String translation = ''}) =>
    Track(
      id: '',
      title: 'Song',
      artist: 'Singer',
      album: '',
      coverUrl: '',
      lyrics: lyrics,
      translation: translation,
    );

PosterDocument _document(
  Track track, {
  String layout = '居中',
  EdgeInsets? pageMargins,
  bool showTranslation = false,
}) => PosterDocument(
  track: track,
  layout: layout,
  dimensions: 'A5 竖版',
  titleSize: 26,
  lyricSize: 16,
  background: Colors.white,
  accent: Colors.indigo,
  overlay: 0,
  pageMargins: pageMargins,
  showTranslation: showTranslation,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('旧海报仍按纸张和版式计算页边距', () {
    for (final (layout, horizontalRatio) in [('居中', .10), ('左对齐', .12)]) {
      final doc = _document(_track(), layout: layout);
      final horizontal = doc.size.width * horizontalRatio;
      final top = (doc.size.width * .1).clamp(30.0, 65.0);
      expect(doc.textWidth, closeTo(doc.size.width - horizontal * 2, .001));
      expect(doc.titleTop, closeTo(doc.size.width * .16, .001));
      expect(doc.lyricTopForPage(1), closeTo(top, .001));
      expect(
        doc.lyricHeightForPage(0),
        closeTo(doc.size.height - doc.lyricTopForPage(0) - 85, .001),
      );
      expect(
        doc.lyricHeightForPage(1),
        closeTo(doc.size.height - top - 85, .001),
      );
    }
  });

  test('自定义页边距改变换行和分页，完整保留原文及译文', () {
    final lyrics = List.generate(
      20,
      (index) => 'Lyric ${index + 1}: a morning light',
    );
    final translation = List.generate(20, (index) => '译文第 ${index + 1} 句');
    final track = _track(
      lyrics: lyrics.join('\n'),
      translation: translation.join('\n'),
    );
    const margins = EdgeInsets.fromLTRB(78, 95, 110, 130);

    for (final bilingual in [false, true]) {
      final baseline = _document(track, showTranslation: bilingual);
      final custom = _document(
        track,
        pageMargins: margins,
        showTranslation: bilingual,
      );
      expect(
        custom.textWidth,
        closeTo(custom.size.width - margins.horizontal, .001),
      );
      expect(custom.lyricTopForPage(1), margins.top);
      expect(
        custom.lyricHeightForPage(1),
        closeTo(custom.size.height - margins.vertical, .001),
      );
      expect(custom.pages.length, greaterThan(baseline.pages.length));
      expect(custom.pages.join(), track.lyrics);

      for (var page = 0; page < custom.pages.length; page++) {
        expect(
          custom.textHeightForPage(page),
          lessThanOrEqualTo(custom.lyricHeightForPage(page)),
        );
        if (!bilingual) continue;
        for (final lyric in custom.pages[page].trimRight().split('\n')) {
          final index = lyrics.indexOf(lyric);
          expect(index, isNonNegative);
          expect(
            custom.pageTextSpan(page).toPlainText(),
            contains('$lyric\n${translation[index]}'),
          );
        }
      }
    }
  });

  testWidgets('预览将左对齐歌词放在自定义的横向页边距内', (tester) async {
    const margins = EdgeInsets.fromLTRB(87, 53, 34, 91);
    final doc = _document(_track(), layout: '左对齐', pageMargins: margins);
    const pageKey = ValueKey('margin-preview');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: PosterPage(key: pageKey, document: doc, page: 0),
        ),
      ),
    );

    final page = tester.getRect(find.byKey(pageKey));
    final lyrics = tester.getRect(find.byKey(const ValueKey('poster-lyrics')));
    expect(lyrics.left - page.left, closeTo(margins.left, .001));
    expect(lyrics.right, lessThanOrEqualTo(page.right - margins.right));
    expect(lyrics.top, greaterThanOrEqualTo(page.top + margins.top));
    expect(lyrics.bottom, lessThanOrEqualTo(page.bottom - margins.bottom));
  });

  testWidgets('排版侧栏以毫米单独修改左边距并可恢复默认值', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 960);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = PosterController()
      ..selected = _track()
      ..currentTab = 1;
    addTearDown(controller.dispose);
    final initialMargins = controller.pageMargins;
    await tester.pumpWidget(
      MaterialApp(
        theme: controller.appTheme,
        home: PosterWorkspace(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('page-margin-left'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    final input = find.descendant(
      of: field,
      matching: find.byType(TextField),
      matchRoot: true,
    );
    await tester.enterText(input, '12.5');
    await tester.pumpAndSettle();
    expect(controller.pageMargins.left, closeTo(12.5 * 72 / 25.4, .001));
    expect(controller.pageMargins.top, initialMargins.top);
    expect(controller.pageMargins.right, initialMargins.right);
    expect(controller.pageMargins.bottom, initialMargins.bottom);

    final reset = find.byKey(const ValueKey('reset-page-margins'));
    await tester.ensureVisible(reset);
    await tester.pumpAndSettle();
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(controller.hasCustomPageMargins, isFalse);
    expect(controller.pageMargins, initialMargins);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('页边距不合适时保留当前值，恢复默认后仍可更换纸张', () {
    final controller = PosterController()..selected = _track();
    addTearDown(controller.dispose);
    expect(controller.hasCustomPageMargins, isFalse);
    expect(
      controller.setPageMargins(const EdgeInsets.fromLTRB(35, 42, 61, 72)),
      isTrue,
    );
    final previous = controller.pageMargins;
    for (final invalid in const [
      EdgeInsets.only(left: -1),
      EdgeInsets.only(top: double.nan),
      EdgeInsets.only(left: 1000),
      EdgeInsets.only(bottom: 1000),
    ]) {
      expect(controller.setPageMargins(invalid), isFalse);
      expect(controller.pageMargins, previous);
    }

    expect(controller.setPageMargins(null), isTrue);
    expect(controller.hasCustomPageMargins, isFalse);
    expect(controller.setDimensions('A5 竖版'), isTrue);
    expect(
      controller.pageMargins,
      PosterDocument.defaultPageMargins(
        controller.document!.size,
        controller.layout,
      ),
    );
  });

  test('海报草稿保存并恢复四边页边距，可恢复自动留白', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = _MemoryStorage();
    final original = PosterController(history: HistoryStore(storage: storage));
    final restored = PosterController(history: HistoryStore(storage: storage));
    addTearDown(original.dispose);
    addTearDown(restored.dispose);
    await original.loadPreferences();
    await original.addManualTrack();
    const margins = EdgeInsets.fromLTRB(41.5, 44, 33, 64);
    expect(original.setPageMargins(margins), isTrue);
    await original.saveDraft();

    await restored.loadPreferences();
    final entry = restored.history.drafts.single;
    await restored.openDraft(entry);
    expect(restored.hasCustomPageMargins, isTrue);
    expect(restored.pageMargins, margins);
    expect(
      restored.document!.textWidth,
      closeTo(restored.document!.size.width - margins.horizontal, .001),
    );

    expect(restored.setPageMargins(null), isTrue);
    await restored.saveDraft();
    await original.openDraft(entry);
    expect(original.hasCustomPageMargins, isFalse);
  });
}
