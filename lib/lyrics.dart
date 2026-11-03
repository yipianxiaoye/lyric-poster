/// Plain lyrics and translation share the same line indices. Missing translated
/// lines remain empty so they cannot drift onto a different original sentence.
class LyricsResult {
  const LyricsResult({required this.lyrics, this.translation = ''});

  final String lyrics, translation;
  bool get hasTranslation => translation.trim().isNotEmpty;
}

class _LrcLine {
  const _LrcLine(this.text, this.time, this.order);
  final String text;
  final int? time;
  final int order;
}

List<(int, int)> _exactTimestampAnchors(
  List<int> originalTimes,
  List<int> translationTimes,
) {
  final lengths = List.generate(
    originalTimes.length + 1,
    (_) => List<int>.filled(translationTimes.length + 1, 0),
  );
  for (var i = originalTimes.length - 1; i >= 0; i--) {
    for (var j = translationTimes.length - 1; j >= 0; j--) {
      lengths[i][j] = originalTimes[i] == translationTimes[j]
          ? lengths[i + 1][j + 1] + 1
          : lengths[i + 1][j] > lengths[i][j + 1]
          ? lengths[i + 1][j]
          : lengths[i][j + 1];
    }
  }

  final anchors = <(int, int)>[];
  var i = 0, j = 0;
  while (i < originalTimes.length && j < translationTimes.length) {
    if (originalTimes[i] == translationTimes[j] &&
        lengths[i][j] == lengths[i + 1][j + 1] + 1) {
      anchors.add((i++, j++));
    } else if (lengths[i + 1][j] >= lengths[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return anchors;
}

Map<int, String> _alignApproximateSegment(
  List<int> originals,
  List<int> translations,
  List<_LrcLine> main,
  List<_LrcLine> translated,
) {
  if (originals.isEmpty || translations.isEmpty) return const {};
  const gapCost = 400.0;
  const maxTimeDifference = 700;
  final cost = List.generate(
    originals.length + 1,
    (_) => List<double>.filled(translations.length + 1, double.infinity),
  );
  final steps = List.generate(
    originals.length + 1,
    (_) => List<int>.filled(translations.length + 1, -1),
  );
  cost[0][0] = 0;
  for (var i = 0; i <= originals.length; i++) {
    for (var j = 0; j <= translations.length; j++) {
      final current = cost[i][j];
      if (!current.isFinite) continue;
      void relax(int nextI, int nextJ, double nextCost, int step) {
        if (nextCost < cost[nextI][nextJ]) {
          cost[nextI][nextJ] = nextCost;
          steps[nextI][nextJ] = step;
        }
      }

      if (i < originals.length) relax(i + 1, j, current + gapCost, 0);
      if (j < translations.length) relax(i, j + 1, current + gapCost, 1);
      if (i < originals.length && j < translations.length) {
        final originalTime = main[originals[i]].time!;
        final translatedTime = translated[translations[j]].time!;
        final difference = (originalTime - translatedTime).abs();
        if (difference > 0 && difference <= maxTimeDifference) {
          relax(i + 1, j + 1, current + difference, 2);
        }
      }
    }
  }
  final aligned = <int, String>{};
  var i = originals.length, j = translations.length;
  while (i > 0 || j > 0) {
    switch (steps[i][j]) {
      case 0:
        i--;
        break;
      case 1:
        j--;
        break;
      case 2:
        aligned[originals[i - 1]] = translated[translations[j - 1]].text;
        i--;
        j--;
        break;
      default:
        throw StateError('歌词时间对齐失败。');
    }
  }
  return aligned;
}

final _timestamp = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
final _metadata = RegExp(r'^\s*\[[a-zA-Z][a-zA-Z0-9_-]*:[^\]]*\]\s*$');

List<_LrcLine> _readLrc(String source) {
  final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final offsetMatch = RegExp(
    r'\[offset:([+-]?\d+)\]',
    caseSensitive: false,
  ).firstMatch(normalized);
  final offset = int.tryParse(offsetMatch?.group(1) ?? '') ?? 0;
  final lines = <_LrcLine>[];
  for (final raw in normalized.split('\n')) {
    if (_metadata.hasMatch(raw)) continue;
    final times = _timestamp.allMatches(raw).toList();
    final text = raw.replaceAll(_timestamp, '').trim();
    if (times.isEmpty) {
      lines.add(_LrcLine(text, null, lines.length));
    } else {
      for (final stamp in times) {
        final fraction = (stamp.group(3) ?? '').padRight(3, '0');
        final milliseconds =
            int.parse(stamp.group(1)!) * 60000 +
            int.parse(stamp.group(2)!) * 1000 +
            int.parse(fraction.isEmpty ? '0' : fraction) +
            offset;
        lines.add(_LrcLine(text, milliseconds, lines.length));
      }
    }
  }
  // Expanding repeated timestamps must retain chronological order, rather than
  // placing every repeat next to its first occurrence. Untimed stanza breaks
  // stay attached to the preceding timed line.
  if (lines.any((line) => line.time != null) &&
      lines
          .where((line) => line.text.isNotEmpty)
          .every((line) => line.time != null)) {
    final sortTimes = <int, int>{};
    var previous = -1;
    for (final line in lines) {
      previous = line.time ?? previous;
      sortTimes[line.order] = previous;
    }
    lines.sort((a, b) {
      final byTime = sortTimes[a.order]!.compareTo(sortTimes[b.order]!);
      return byTime != 0 ? byTime : a.order.compareTo(b.order);
    });
  }
  while (lines.isNotEmpty && lines.first.text.isEmpty) {
    lines.removeAt(0);
  }
  while (lines.isNotEmpty && lines.last.text.isEmpty) {
    lines.removeLast();
  }
  return lines;
}

/// Matches NetEase's original and translated LRC by time. Index matching is
/// restricted to untimed documents with exactly the same number of lines.
LyricsResult parseLyrics(String original, String translated) {
  final main = _readLrc(original);
  final translation = _readLrc(translated);
  if (main.isEmpty) {
    return LyricsResult(
      lyrics: translation.map((line) => line.text).join('\n'),
    );
  }
  final lyrics = main.map((line) => line.text).join('\n');
  if (translation.isEmpty) return LyricsResult(lyrics: lyrics);
  final mainHasTimes = main.any((line) => line.time != null);
  final translationHasTimes = translation.any((line) => line.time != null);
  final aligned = List<String>.filled(main.length, '');
  if (!mainHasTimes && !translationHasTimes) {
    if (main.length == translation.length) {
      for (var index = 0; index < main.length; index++) {
        if (main[index].text.isNotEmpty) {
          aligned[index] = translation[index].text;
        }
      }
    }
  } else {
    final originals = [
      for (var index = 0; index < main.length; index++)
        if (main[index].time != null && main[index].text.isNotEmpty) index,
    ];
    final translations = [
      for (var index = 0; index < translation.length; index++)
        if (translation[index].time != null &&
            translation[index].text.isNotEmpty)
          index,
    ];
    final exactAnchors = _exactTimestampAnchors(
      [for (final index in originals) main[index].time!],
      [for (final index in translations) translation[index].time!],
    );
    final matched = <int, String>{};
    var previousOriginal = -1, previousTranslation = -1;
    for (final anchor in [
      ...exactAnchors,
      (originals.length, translations.length),
    ]) {
      final (anchorOriginal, anchorTranslation) = anchor;
      matched.addAll(
        _alignApproximateSegment(
          originals.sublist(previousOriginal + 1, anchorOriginal),
          translations.sublist(previousTranslation + 1, anchorTranslation),
          main,
          translation,
        ),
      );
      if (anchorOriginal < originals.length) {
        matched[originals[anchorOriginal]] =
            translation[translations[anchorTranslation]].text;
      }
      previousOriginal = anchorOriginal;
      previousTranslation = anchorTranslation;
    }
    final repeated = <(int, String), String>{};
    for (final entry in matched.entries) {
      final line = main[entry.key];
      final key = (line.time!, line.text);
      repeated.putIfAbsent(key, () => entry.value);
    }
    for (var index = 0; index < main.length; index++) {
      final line = main[index];
      if (line.time == null || line.text.isEmpty) continue;
      aligned[index] =
          matched[index] ?? repeated[(line.time!, line.text)] ?? '';
    }
  }
  return LyricsResult(
    lyrics: lyrics,
    translation: aligned.any((line) => line.isNotEmpty)
        ? aligned.join('\n')
        : '',
  );
}
