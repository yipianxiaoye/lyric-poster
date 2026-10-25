import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class Track {
  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.coverUrl,
    this.lyrics = '',
    this.durationMs = 0,
  });
  final String id;
  String title, artist, album, coverUrl, lyrics;
  int durationMs;
}

class NeteaseClient {
  NeteaseClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String? playlistTitle;
  static const _headers = {
    'User-Agent': 'LyricPoster/1.0 (Flutter)',
    'Accept': 'application/json',
  };
  static const _songBatchSize = 100;

  String? parsePlaylistId(String value) {
    final input = value.trim();
    if (RegExp(r'^\d+$').hasMatch(input)) return input;
    return RegExp(
      r'(?:playlist|id)[^\d]{0,5}(\d{4,})',
    ).firstMatch(input)?.group(1);
  }

  Future<List<Track>> fetchPlaylist(String input) async {
    final id = parsePlaylistId(input);
    if (id == null) {
      throw const FormatException('没有找到有效的歌单 ID，请粘贴网易云歌单链接或数字 ID。');
    }
    // The legacy detail API returns `result` and can silently truncate a
    // playlist to 10 tracks. v6 exposes the complete ordered `trackIds` list.
    final data = await _getJson('/api/v6/playlist/detail', {
      'id': id,
      'n': '1000',
      's': '0',
    });
    final playlist = data['playlist'] ?? data['result'];
    if (playlist is! Map<String, dynamic>) {
      throw Exception('网易云返回的歌单数据无法识别，请稍后重试。');
    }

    final tracksById = <String, Track>{};
    for (final raw in _maps(playlist['tracks'])) {
      final track = _track(raw);
      if (track.id.isNotEmpty) tracksById[track.id] = track;
    }
    final ids = _maps(playlist['trackIds'])
        .map((raw) => '${raw['id'] ?? ''}')
        .where((id) => RegExp(r'^\d+$').hasMatch(id))
        .toSet()
        .toList();
    final missing = ids.where((id) => !tracksById.containsKey(id)).toList();
    for (var start = 0; start < missing.length; start += _songBatchSize) {
      final batch = missing.skip(start).take(_songBatchSize);
      final details = await _getJson('/api/v3/song/detail', {
        'c': jsonEncode(batch.map((id) => {'id': id}).toList()),
      });
      if (details['songs'] is! List) {
        throw Exception('网易云返回的歌曲数据无法识别，请稍后重试。');
      }
      for (final raw in _maps(details['songs'])) {
        final track = _track(raw);
        if (track.id.isNotEmpty) tracksById[track.id] = track;
      }
    }

    // Song detail responses may use a different order from the playlist.
    final tracks = ids.isEmpty
        ? tracksById.values.toList()
        : ids.map((id) => tracksById[id]).whereType<Track>().toList();
    final declaredCount = (playlist['trackCount'] as num?)?.toInt() ?? 0;
    final expectedCount = declaredCount > ids.length
        ? declaredCount
        : ids.length;
    if (tracks.length < expectedCount) {
      throw Exception(
        '仅能读取歌单中的 ${tracks.length}/$expectedCount 首歌曲，尚未完成导入。'
        '部分歌曲可能已下架或暂不可访问，请稍后重试。',
      );
    }
    if (tracks.isEmpty) throw Exception('这个歌单目前没有歌曲。');
    final name = playlist['name'];
    playlistTitle = name is String && name.trim().isNotEmpty
        ? name.trim()
        : null;
    return tracks;
  }

  Future<String> fetchLyrics(String trackId) async {
    final data = await _getJson('/api/song/lyric', {
      'id': trackId,
      'lv': '1',
      'kv': '1',
      'tv': '-1',
    });
    final lrc = data['lrc'] as Map<String, dynamic>?;
    final main = _strip('${lrc?['lyric'] ?? ''}');
    if (main.isNotEmpty) return main;
    final translation = data['tlyric'] as Map<String, dynamic>?;
    return _strip('${translation?['lyric'] ?? ''}');
  }

  /// Search the public NetEase catalogue. Search results can be selected and
  /// added to the working library without replacing an imported playlist.
  Future<List<Track>> searchSongs(String query, {int limit = 30}) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return const [];
    final data = await _getJson('/api/cloudsearch/pc', {
      's': keyword,
      'type': '1',
      'offset': '0',
      'limit': '${limit.clamp(1, 100)}',
    });
    final result = data['result'];
    if (result is! Map<String, dynamic>) return const [];
    return _maps(
      result['songs'],
    ).map(_track).where((track) => track.id.isNotEmpty).toList();
  }

  Future<Map<String, dynamic>> _getJson(
    String path,
    Map<String, String> query,
  ) async {
    http.Response response;
    try {
      response = await _client
          .get(Uri.https('music.163.com', path, query), headers: _headers)
          .timeout(const Duration(seconds: 18));
    } on TimeoutException {
      throw Exception('连接网易云超时，请检查网络后重试。');
    } on http.ClientException {
      throw Exception('无法连接网易云，请检查网络后重试。');
    }
    if (response.statusCode != 200) {
      throw Exception('网易云返回 HTTP ${response.statusCode}，请稍后重试。');
    }
    dynamic data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw Exception('网易云返回的数据无法识别，请稍后重试。');
    }
    if (data is! Map<String, dynamic>) {
      throw Exception('网易云返回的数据无法识别，请稍后重试。');
    }
    final code = '${data['code'] ?? 200}';
    if (code != '200') {
      if (code == '404') throw Exception('歌单不存在或已被删除，请检查链接或歌单 ID。');
      final message = '${data['message'] ?? data['msg'] ?? '暂时无法读取数据'}';
      throw Exception('网易云返回：$message（错误码 $code）。');
    }
    return data;
  }

  static Iterable<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value.whereType<Map<String, dynamic>>()
      : const <Map<String, dynamic>>[];

  static Track _track(Map<String, dynamic> raw) {
    final artists = _maps(raw['ar'] ?? raw['artists']);
    final artist = artists
        .map((item) => '${item['name'] ?? ''}')
        .where((name) => name.isNotEmpty)
        .join(' / ');
    final album = (raw['al'] ?? raw['album']) as Map<String, dynamic>? ?? {};
    final coverUrl = '${album['picUrl'] ?? ''}';
    return Track(
      id: '${raw['id'] ?? ''}',
      title: '${raw['name'] ?? '未命名歌曲'}',
      artist: artist.isEmpty ? '未知歌手' : artist,
      album: '${album['name'] ?? '未知专辑'}',
      coverUrl: coverUrl.replaceFirst(RegExp(r'^http://'), 'https://'),
      durationMs: ((raw['dt'] ?? raw['duration']) as num?)?.toInt() ?? 0,
    );
  }

  String _strip(String value) => value
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'\[[0-9:.]+\]'), '').trim())
      .where(
        (line) =>
            line.isNotEmpty &&
            !line.startsWith('[by:') &&
            !line.startsWith('[ti:'),
      )
      .join('\n');

  void close() => _client.close();
}
