import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'history_storage.dart';
import 'history_storage_io.dart'
    if (dart.library.html) 'history_storage_web.dart';
import 'netease_client.dart';

Map<String, dynamic> trackToMap(Track track) => {
  'id': track.id,
  'title': track.title,
  'artist': track.artist,
  'album': track.album,
  'coverUrl': track.coverUrl,
  'lyrics': track.lyrics,
  'durationMs': track.durationMs,
};

Track trackFromMap(Map<String, dynamic> data) => Track(
  id: data['id'] as String,
  title: data['title'] as String,
  artist: data['artist'] as String,
  album: data['album'] as String,
  coverUrl: data['coverUrl'] as String,
  lyrics: data['lyrics'] as String? ?? '',
  durationMs: (data['durationMs'] as num?)?.toInt() ?? 0,
);

class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.updatedAt,
    this.source = '',
    this.trackCount = 0,
  });
  final String id, title, subtitle, source;
  final DateTime updatedAt;
  final int trackCount;

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'updatedAt': updatedAt.toIso8601String(),
    'source': source,
    'trackCount': trackCount,
  };

  factory HistoryEntry.fromMap(Map<String, dynamic> data) {
    final id = data['id'] as String;
    if (!RegExp(r'^(playlist|draft)-[0-9]+$').hasMatch(id)) {
      throw const FormatException('无效的历史记录');
    }
    return HistoryEntry(
      id: id,
      title: data['title'] as String,
      subtitle: data['subtitle'] as String,
      updatedAt: DateTime.parse(data['updatedAt'] as String),
      source: data['source'] as String? ?? '',
      trackCount: (data['trackCount'] as num?)?.toInt() ?? 0,
    );
  }
}

// Run the potentially large image encoding outside the UI isolate. Each draft
// owns its media, so deleting a draft also removes its background and stickers.
String _encodePayload(Map<String, dynamic> data) {
  dynamic encode(dynamic value) {
    if (value is Uint8List) return {'_bytes': base64Encode(value)};
    if (value is Map) {
      return value.map((key, item) => MapEntry(key, encode(item)));
    }
    if (value is List) return value.map(encode).toList();
    return value;
  }

  return jsonEncode(encode(data));
}

Map<String, dynamic> _decodePayload(String source) {
  dynamic decode(dynamic value) {
    if (value is Map<String, dynamic>) {
      if (value.length == 1 && value['_bytes'] is String) {
        return base64Decode(value['_bytes'] as String);
      }
      return value.map((key, item) => MapEntry(key, decode(item)));
    }
    if (value is List) return value.map(decode).toList();
    return value;
  }

  return decode(jsonDecode(source)) as Map<String, dynamic>;
}

class HistoryStore extends ChangeNotifier {
  HistoryStore({HistoryStorage? storage})
    : storage = storage ?? LocalHistoryStorage();
  final HistoryStorage storage;
  final playlists = <HistoryEntry>[];
  final drafts = <HistoryEntry>[];
  Future<void>? _loading;
  Future<void> _pending = Future.value();
  bool _disposed = false;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final source = await storage.read('index');
    if (source == null) return;
    final data = jsonDecode(source) as Map<String, dynamic>;
    for (final (key, target) in [
      ('playlists', playlists),
      ('drafts', drafts),
    ]) {
      for (final raw in data[key] as List? ?? []) {
        try {
          target.add(
            HistoryEntry.fromMap(Map<String, dynamic>.from(raw as Map)),
          );
        } catch (_) {
          // A damaged entry must not hide the rest of the library.
        }
      }
      _sort(target);
    }
    _changed();
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final next = _pending.then((_) async {
      await load();
      return operation();
    });
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> _writeIndex() => storage.write(
    'index',
    jsonEncode({
      'version': 1,
      'playlists': playlists.map((item) => item.toMap()).toList(),
      'drafts': drafts.map((item) => item.toMap()).toList(),
    }),
  );

  void _sort(List<HistoryEntry> items) =>
      items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<void> _put(
    HistoryEntry entry,
    Map<String, dynamic> payload,
    List<HistoryEntry> target,
  ) async {
    await storage.write(entry.id, await compute(_encodePayload, payload));
    final previous = List<HistoryEntry>.of(target);
    target.removeWhere((item) => item.id == entry.id);
    target.add(entry);
    _sort(target);
    try {
      await _writeIndex();
    } catch (_) {
      target
        ..clear()
        ..addAll(previous);
      rethrow;
    }
    _changed();
  }

  Future<void> savePlaylist(String id, String title, List<Track> tracks) {
    final payload = {'tracks': tracks.map(trackToMap).toList()};
    final entry = HistoryEntry(
      id: 'playlist-$id',
      title: title,
      subtitle: '网易云歌单 $id',
      updatedAt: DateTime.now(),
      source: 'https://music.163.com/playlist?id=$id',
      trackCount: tracks.length,
    );
    return _serial(() => _put(entry, payload, playlists));
  }

  Future<void> saveDraft(String id, Map<String, dynamic> state) {
    final track = state['track'] as Map<String, dynamic>;
    final entry = HistoryEntry(
      id: id,
      title: track['title'] as String,
      subtitle: '${track['artist']} · ${state['dimensions']}',
      updatedAt: DateTime.now(),
    );
    return _serial(() => _put(entry, state, drafts));
  }

  Future<Map<String, dynamic>> readEntry(String id) => _serial(() async {
    final source = await storage.read(id);
    if (source == null) throw const FormatException('记录文件已丢失');
    return compute(_decodePayload, source);
  });

  Future<void> delete(HistoryEntry entry, {required bool playlist}) =>
      _serial(() async {
        final target = playlist ? playlists : drafts;
        final previous = List<HistoryEntry>.of(target);
        target.removeWhere((item) => item.id == entry.id);
        try {
          await _writeIndex();
        } catch (_) {
          target
            ..clear()
            ..addAll(previous);
          rethrow;
        }
        await storage.remove(entry.id);
        _changed();
      });

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
