import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyric_poster/netease_client.dart';

http.Response jsonResponse(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object> song(int id) => {
  'id': id,
  'name': '歌曲 $id',
  'ar': [
    {'name': '歌手'},
  ],
  'al': {'name': '专辑', 'picUrl': 'http://p1.music.126.net/cover.jpg'},
  'dt': 315600,
};

void main() {
  test('分享参数不影响 11 位歌单 ID，兼容 result 和旧歌曲字段', () async {
    var requests = 0;
    final client = NeteaseClient(
      client: MockClient((request) async {
        requests++;
        expect(request.url.path, '/api/v6/playlist/detail');
        expect(request.url.queryParameters['id'], '19123456789');
        expect(request.url.queryParameters.containsKey('uct2'), isFalse);
        return jsonResponse({
          'code': 200,
          'result': {
            'trackCount': 1,
            'tracks': [
              {
                'id': 1992745596,
                'name': '测试歌曲',
                'artists': [
                  {'name': '甲'},
                  {'name': '乙'},
                ],
                'album': {
                  'name': '测试专辑',
                  'picUrl': 'http://p2.music.126.net/cover.jpg',
                },
                'duration': 315600,
              },
            ],
          },
        });
      }),
    );
    addTearDown(client.close);
    final tracks = await client.fetchPlaylist(
      '分享歌单 https://music.163.com/playlist?id=19123456789&uct2=share/test+=',
    );
    expect(requests, 1);
    expect(tracks.single.id, '1992745596');
    expect(tracks.single.title, '测试歌曲');
    expect(tracks.single.artist, '甲 / 乙');
    expect(tracks.single.album, '测试专辑');
    expect(tracks.single.durationMs, 315600);
    expect(tracks.single.coverUrl, 'https://p2.music.126.net/cover.jpg');
  });

  test('补齐预览之外的全部歌曲，分批请求并保留歌单顺序', () async {
    final ids = List.generate(205, (index) => 10000 + index);
    final batches = <List<String>>[];
    final client = NeteaseClient(
      client: MockClient((request) async {
        if (request.url.path == '/api/v6/playlist/detail') {
          return jsonResponse({
            'code': 200,
            'playlist': {
              'trackCount': ids.length,
              'tracks': [song(10005)],
              'trackIds': ids.map((id) => {'id': id}).toList(),
            },
          });
        }
        expect(request.url.path, '/api/v3/song/detail');
        final c = jsonDecode(request.url.queryParameters['c']!) as List;
        final batch = c.map((item) => '${item['id']}').toList();
        batches.add(batch);
        return jsonResponse({
          'code': 200,
          'songs': batch.reversed.map((id) => song(int.parse(id))).toList(),
        });
      }),
    );
    addTearDown(client.close);
    final tracks = await client.fetchPlaylist('19123456789');
    expect(tracks.map((track) => track.id), ids.map((id) => '$id'));
    expect(batches.map((batch) => batch.length), [100, 100, 4]);
    expect(batches.expand((batch) => batch), isNot(contains('10005')));
    expect(tracks.first.artist, '歌手');
    expect(tracks.first.album, '专辑');
    expect(tracks.first.durationMs, 315600);
  });

  test('trackIds 有内容时，即使预览为空也能读取', () async {
    final client = NeteaseClient(
      client: MockClient((request) async {
        if (request.url.path == '/api/v6/playlist/detail') {
          return jsonResponse({
            'code': 200,
            'playlist': {
              'trackCount': 1,
              'tracks': [],
              'trackIds': [
                {'id': 12345},
              ],
            },
          });
        }
        return jsonResponse({
          'code': 200,
          'songs': [song(12345)],
        });
      }),
    );
    addTearDown(client.close);
    expect((await client.fetchPlaylist('19123456789')).single.id, '12345');
  });

  test('HTTP 200 中的网易云错误保留具体原因', () async {
    for (final response in [
      {'code': 404, 'message': '歌单不存在'},
      {'code': 401, 'message': '需要登录'},
    ]) {
      final client = NeteaseClient(
        client: MockClient((_) async => jsonResponse(response)),
      );
      addTearDown(client.close);
      await expectLater(
        client.fetchPlaylist('19123456789'),
        throwsA(
          isException.having(
            (error) => error.toString(),
            'message',
            contains(response['code'] == 404 ? '不存在' : '需要登录'),
          ),
        ),
      );
    }
  });

  test('缺少歌曲详情时不把部分导入误报为成功', () async {
    final client = NeteaseClient(
      client: MockClient((request) async {
        if (request.url.path == '/api/v6/playlist/detail') {
          return jsonResponse({
            'code': 200,
            'playlist': {
              'trackCount': 2,
              'tracks': [song(12345)],
              'trackIds': [
                {'id': 12345},
                {'id': 23456},
              ],
            },
          });
        }
        return jsonResponse({'code': 200, 'songs': []});
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.fetchPlaylist('19123456789'),
      throwsA(
        isException.having((e) => e.toString(), 'message', contains('1/2')),
      ),
    );
  });

  test('空歌单和无法识别的响应分别提示', () async {
    final cases = <(Object, String)>[
      (
        {
          'code': 200,
          'playlist': {'trackCount': 0, 'tracks': []},
        },
        '目前没有歌曲',
      ),
      ({'code': 200}, '数据无法识别'),
    ];
    for (final (response, message) in cases) {
      final client = NeteaseClient(
        client: MockClient((_) async => jsonResponse(response)),
      );
      addTearDown(client.close);
      await expectLater(
        client.fetchPlaylist('19123456789'),
        throwsA(
          isException.having(
            (error) => error.toString(),
            'message',
            contains(message),
          ),
        ),
      );
    }
  });

  test('HTTP 失败或非 JSON 响应不会被误报为空歌单', () async {
    for (final (response, message) in [
      (http.Response('Forbidden', 403), 'HTTP 403'),
      (http.Response('<html>Unavailable</html>', 200), '数据无法识别'),
    ]) {
      final client = NeteaseClient(client: MockClient((_) async => response));
      addTearDown(client.close);
      await expectLater(
        client.fetchPlaylist('19123456789'),
        throwsA(
          isException.having(
            (error) => error.toString(),
            'message',
            contains(message),
          ),
        ),
      );
    }
  });

  test('歌词以 UTF-8 解码并移除时间标签', () async {
    final client = NeteaseClient(
      client: MockClient((request) async {
        expect(request.url.path, '/api/song/lyric');
        return jsonResponse({
          'code': 200,
          'lrc': {'lyric': '[ti:测试]\n[00:01.20]第一行\n[00:03.40]第二行'},
        });
      }),
    );
    addTearDown(client.close);
    expect(await client.fetchLyrics('12345'), '第一行\n第二行');
  });

  test('歌曲搜索返回可加入工作区的歌曲', () async {
    final client = NeteaseClient(
      client: MockClient((request) async {
        expect(request.url.path, '/api/cloudsearch/pc');
        expect(request.url.queryParameters['s'], '海阔天空');
        expect(request.url.queryParameters['type'], '1');
        return jsonResponse({
          'code': 200,
          'result': {
            'songs': [song(7788)],
          },
        });
      }),
    );
    addTearDown(client.close);
    final results = await client.searchSongs('海阔天空');
    expect(results, hasLength(1));
    expect(results.single.id, '7788');
    expect(results.single.title, '歌曲 7788');
  });
}
