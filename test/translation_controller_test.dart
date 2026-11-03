import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyric_poster/font_library.dart';
import 'package:lyric_poster/history_storage.dart';
import 'package:lyric_poster/history_store.dart';
import 'package:lyric_poster/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryStorage implements HistoryStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> remove(String key) async => values.remove(key);
}

Track sample({String lyrics = ''}) => Track(
  id: '123',
  title: 'Hello',
  artist: 'Singer',
  album: '',
  coverUrl: '',
  lyrics: lyrics,
);

http.Response response() => http.Response(
  jsonEncode({
    'code': 200,
    'lrc': {'lyric': '[00:01.00]Hello\n[00:02.00]Goodbye'},
    'tlyric': {'lyric': '[00:01.00]你好\n[00:02.00]再见'},
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('选择歌曲同时获取原文与译文，后续选择不重复请求', () async {
    var requests = 0;
    final client = NeteaseClient(
      client: MockClient((_) async {
        requests++;
        return response();
      }),
    );
    final controller = PosterController(client: client);
    addTearDown(controller.dispose);
    final track = sample();
    await controller.selectTrack(track);
    expect(track.lyrics, 'Hello\nGoodbye');
    expect(track.translation, '你好\n再见');
    expect(track.translationFetched, isTrue);
    expect(controller.document!.showTranslation, isTrue);
    await controller.selectTrack(sample()..translationFetched = true);
    await controller.selectTrack(track);
    expect(requests, 1);
  });

  test('旧歌词可补充译文，修改过的原文不被覆盖或配上错误译文', () async {
    final controller = PosterController(
      client: NeteaseClient(client: MockClient((_) async => response())),
    );
    addTearDown(controller.dispose);
    final existing = sample(lyrics: 'Hello\nGoodbye');
    await controller.selectTrack(existing);
    expect(existing.translation, '你好\n再见');
    final edited = sample(lyrics: 'Edited\nGoodbye');
    await controller.selectTrack(edited);
    expect(edited.lyrics, 'Edited\nGoodbye');
    expect(edited.translation, isEmpty);
    expect(controller.translationError, contains('当前原文已修改'));
  });

  test('下载期间手动填写的译文不会被异步响应覆盖', () async {
    final pending = Completer<http.Response>();
    final controller = PosterController(
      client: NeteaseClient(client: MockClient((_) => pending.future)),
    );
    addTearDown(controller.dispose);
    final track = sample(lyrics: 'Hello\nGoodbye');
    controller.selected = track;
    final fetch = controller.loadTrackLyrics(track);
    expect(controller.lyricsLoading, isTrue);
    expect(controller.updateSelected(translation: '您好\n再会'), isTrue);
    pending.complete(response());
    await fetch;
    expect(track.translation, '您好\n再会');
    expect(controller.lyricsLoading, isFalse);
  });

  test('旧原文含前导空行时补充译文仍逐行对齐', () async {
    final controller = PosterController(
      client: NeteaseClient(client: MockClient((_) async => response())),
    );
    addTearDown(controller.dispose);
    final track = sample(lyrics: '\n  \nHello\nGoodbye\n');
    await controller.selectTrack(track);
    expect(track.lyrics, '\n  \nHello\nGoodbye\n');
    expect(track.translation, '\n\n你好\n再见');
    expect(
      controller.document!.pageTextSpan(0).toPlainText(),
      'Hello\n你好\nGoodbye\n再见',
    );
  });

  test('下载期间清空原文或将译文改回空串也保留用户操作', () async {
    for (final editOriginal in [true, false]) {
      final pending = Completer<http.Response>();
      final controller = PosterController(
        client: NeteaseClient(client: MockClient((_) => pending.future)),
      );
      final track = sample(lyrics: 'Hello\nGoodbye');
      controller.selected = track;
      final fetch = controller.loadTrackLyrics(track);
      if (editOriginal) {
        expect(controller.updateSelected(lyrics: ''), isTrue);
      } else {
        expect(controller.updateSelected(translation: '您好\n再会'), isTrue);
        expect(controller.updateSelected(translation: ''), isTrue);
      }
      pending.complete(response());
      await fetch;
      expect(track.lyrics, editOriginal ? '' : 'Hello\nGoodbye');
      expect(track.translation, isEmpty);
      controller.dispose();
    }
  });

  test('双语设置随草稿恢复，且不改变原文字体字号', () async {
    final storage = MemoryStorage();
    final controller = PosterController(
      history: HistoryStore(storage: storage),
    );
    await controller.loadPreferences();
    controller.selected = sample(lyrics: 'Hello\nGoodbye')
      ..translation = '你好\n再见';
    controller.fonts.fonts.add(const ImportedFont(id: 'f123', name: '译文字体'));
    expect(controller.setTranslationFont('Imported_f123'), isTrue);
    expect(controller.setTranslationSize(18.5), isTrue);
    expect(controller.lyricSize, 15);
    expect(controller.fonts.selectedFamily, defaultFontFamily);
    await controller.saveDraft();
    final entry = controller.history.drafts.single;
    final restored = PosterController(history: HistoryStore(storage: storage));
    await restored.loadPreferences();
    restored.fonts.fonts.add(const ImportedFont(id: 'f123', name: '译文字体'));
    await restored.openDraft(entry);
    expect(restored.selected!.translation, '你好\n再见');
    expect(restored.translationSize, 18.5);
    expect(restored.translationFontFamily, 'Imported_f123');
    expect(restored.document!.translationStyle.fontSize, 18.5);
    expect(restored.document!.translationStyle.fontFamily, 'Imported_f123');
    expect(restored.document!.lyricStyle.fontSize, 15);
    expect(restored.setShowTranslation(false), isTrue);
    await restored.saveDraft();
    await controller.openDraft(restored.history.drafts.single);
    expect(controller.showTranslation, isFalse);
    controller.dispose();
    restored.dispose();
  });

  test('译文显隐和字号默认设置在重启后保留', () async {
    final first = PosterController();
    await first.loadPreferences();
    expect(first.setShowTranslation(false), isTrue);
    expect(first.setTranslationSize(17.5), isTrue);
    await Future<void>.delayed(Duration.zero);
    first.dispose();
    final restored = PosterController();
    await restored.loadPreferences();
    expect(restored.showTranslation, isFalse);
    expect(restored.translationSize, 17.5);
    restored.dispose();
  });

  test('增删原文行清空译文以避免错位，超出原文行数的译文不被保存', () {
    final controller = PosterController()
      ..selected = sample(lyrics: 'Hello\nGoodbye');
    addTearDown(controller.dispose);
    expect(controller.updateSelected(translation: '你好\n再见'), isTrue);
    expect(controller.updateSelected(translation: '你好\n再见\n多余行'), isFalse);
    expect(controller.selected!.translation, '你好\n再见');
    expect(controller.updateSelected(lyrics: 'New\nHello\nGoodbye'), isTrue);
    expect(controller.selected!.translation, isEmpty);
    controller.selected!.lyrics = 'Hello\nGoodbye';
    controller.selected!.translation = '你好\n再见';
    controller.selected!.translationFetched = true;
    expect(controller.updateSelected(lyrics: 'Edited\nGoodbye'), isTrue);
    expect(controller.selected!.translation, isEmpty);
    expect(controller.selected!.translationFetched, isFalse);
    expect(controller.setTranslationSize(double.nan), isFalse);
    expect(controller.setTranslationSize(97), isFalse);
    expect(controller.setTranslationFont('missing'), isFalse);
  });
}
