import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_poster/history_store.dart';
import 'package:lyric_poster/netease_client.dart';

void main() {
  test('按时间对齐错开少量时间的译文，不把缺译文挪到下一句', () {
    final result = parseLyrics(
      '[ti:Song]\n[00:01.00]Hello\n[00:02.00]World\n[00:03.00]Again',
      '[ti:译文]\n[00:01.20]你好\n[00:03.10]再一次',
    );
    expect(result.lyrics, 'Hello\nWorld\nAgain');
    expect(result.translation, '你好\n\n再一次');
  });

  test('多时间标签、相同时间的重复原句和空行保留一致行数', () {
    final result = parseLyrics(
      '[00:01.00]重复\n[00:02.00][00:03.00]副歌\n\n[00:04.00]重复',
      '[00:01.00]同一句\n[00:02.00]副歌译文\n[00:03.00]副歌译文\n[00:04.00]同一句',
    );
    expect(result.lyrics, '重复\n副歌\n副歌\n\n重复');
    expect(result.translation, '同一句\n副歌译文\n副歌译文\n\n同一句');
    expect(
      result.lyrics.split('\n'),
      hasLength(result.translation.split('\n').length),
    );
  });

  test('无时间戳时只在行数相同的情况下对应译文', () {
    expect(parseLyrics('First\nSecond', '第一句\n第二句').translation, '第一句\n第二句');
    expect(parseLyrics('First\nSecond', '第一句').translation, isEmpty);
    expect(parseLyrics('[00:01.00]First', '第一句').translation, isEmpty);
  });

  test('拉取结果保留两个歌词轨道，译文没有内容时返回空串', () {
    final translated = parseLyrics('[00:01.00]Hello', '[00:01.00]你好');
    final track = Track(
      id: '1',
      title: 'Song',
      artist: 'Singer',
      album: 'Album',
      coverUrl: '',
      lyrics: translated.lyrics,
      translation: translated.translation,
      translationFetched: true,
    );
    final restored = trackFromMap(trackToMap(track));
    expect(restored.lyrics, 'Hello');
    expect(restored.translation, '你好');
    expect(restored.translationFetched, isTrue);
    final oldData = Map<String, dynamic>.from(trackToMap(track))
      ..remove('translation')
      ..remove('translationFetched');
    final oldTrack = trackFromMap(oldData);
    expect(oldTrack.translation, isEmpty);
    expect(oldTrack.translationFetched, isFalse);
  });

  test('相同时间的不同句不复用译文，重复句可复用已配对的译文', () {
    final result = parseLyrics(
      '[00:01.00]Hello\n[00:01.00]Hello\n[00:02.00]One\n[00:02.00]Two',
      '[00:01.00]你好\n[00:02.00]一\n[00:02.00]二',
    );
    expect(result.translation, '你好\n你好\n一\n二');
  });

  test('时间标签展开后按时间排列并应用偏移，远离的译文不误配', () {
    final result = parseLyrics(
      '[ar:Artist]\n[al:Album]\n[offset:100]\n[00:01.00][00:03.00]Again\n[00:02.00]Middle',
      '[00:01.10]再次\n[00:02.10]中间\n[00:03.10]再次\n[00:10.00]没有对应原句',
    );
    expect(result.lyrics, 'Again\nMiddle\nAgain');
    expect(result.translation, '再次\n中间\n再次');
    expect(parseLyrics('[00:01.00]Hello', '[00:10.00]你好').translation, isEmpty);
  });

  test('精确时间戳固定为锚点，附近额外译文不能抢占其原句', () {
    final result = parseLyrics(
      '[00:01.000]A\n[00:01.100]B',
      '[00:01.100]乙\n[00:01.200]多余译文',
    );
    expect(result.translation, '\n乙');
  });
}
