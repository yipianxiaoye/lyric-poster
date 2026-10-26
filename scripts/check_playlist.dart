import 'dart:io';

import 'package:lyric_poster/netease_client.dart';

// Explicit live API check; this is not part of the offline test suite.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run scripts/check_playlist.dart <playlist link or ID> [expected count]',
    );
    exitCode = 64;
    return;
  }
  final client = NeteaseClient();
  try {
    final tracks = await client.fetchPlaylist(args.first);
    final expectedCount = args.length > 1 ? int.parse(args[1]) : null;
    if (expectedCount != null && tracks.length != expectedCount) {
      throw StateError(
        'Expected $expectedCount songs; received ${tracks.length}.',
      );
    }
    if (tracks.map((track) => track.id).toSet().length != tracks.length) {
      throw StateError('The imported playlist contains duplicate song IDs.');
    }
    final lyrics = await client.fetchLyrics(tracks.first.id);
    stdout.writeln('Imported ${tracks.length} songs in playlist order.');
    stdout.writeln('First: ${tracks.first.title} / ${tracks.first.artist}');
    stdout.writeln('Last: ${tracks.last.title} / ${tracks.last.artist}');
    stdout.writeln(
      'First song lyric lines: ${lyrics.split('\n').where((line) => line.isNotEmpty).length}',
    );
    if (lyrics.isEmpty) {
      throw StateError('The first song has no readable lyrics.');
    }
  } finally {
    client.close();
  }
}
