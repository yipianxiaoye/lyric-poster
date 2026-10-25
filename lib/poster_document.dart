import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'netease_client.dart';
import 'font_library.dart';

/// Layout is measured in PDF points, independent of the preview's screen size.
class PosterDocument {
  PosterDocument({
    required Track track,
    required this.layout,
    required String dimensions,
    required double titleSize,
    required double lyricSize,
    required this.background,
    required this.accent,
    required this.overlay,
    this.backgroundImage,
    this.backgroundOffset = Offset.zero,
    this.backgroundScale = 1,
    this.stickers = const [],
    this.showPageNumbers = true,
    this.useAlbumCover = false,
    this.fontFamily = defaultFontFamily,
    this.maxLinesPerPage = 24,
    this.topWatermark,
    this.bottomWatermark = '词笺 · LYRIC POSTER',
    this.showTopWatermark = true,
    this.showBottomWatermark = true,
    this.showTopDecoration = true,
  }) : title = track.title,
       artist = track.artist,
       album = track.album,
       coverUrl = track.coverUrl,
       size = paperSize(dimensions) {
    horizontalMargin = size.width * (layout == '左对齐' ? .12 : .1);
    textWidth = size.width - horizontalMargin * 2;
    titleStyle = TextStyle(
      inherit: false,
      fontFamily: fontFamily,
      fontFamilyFallback: chineseFontFallback,
      color: foreground,
      fontSize: titleSize,
      height: 1.15,
      fontWeight: FontWeight.w600,
    );
    artistStyle = TextStyle(
      inherit: false,
      fontFamily: fontFamily,
      fontFamilyFallback: chineseFontFallback,
      color: readableAccent,
      fontSize: 16,
      height: 1.3,
      fontWeight: FontWeight.w600,
    );
    lyricStyle = TextStyle(
      inherit: false,
      fontFamily: fontFamily,
      fontFamilyFallback: chineseFontFallback,
      color: foreground.withValues(alpha: .94),
      fontSize: lyricSize,
      height: 1.55,
    );
    titleTop = (size.width * .16).clamp(36, size.height * .18);
    // Limit exceptionally long headings, reserving room for the lyrics.
    titleHeight = measure(
      title,
      titleStyle,
      textWidth,
    ).clamp(titleSize * 1.15, titleSize * 2.3);
    artistTop = titleTop + titleHeight + 10;
    artistHeight = measure(artist, artistStyle, textWidth).clamp(20.8, 41.6);
    lyricTop = artistTop + artistHeight + 28;
    lyricHeight = size.height - lyricTop - 85;
    if (lyricHeight < lyricSize * 1.55) {
      throw StateError('标题和歌手信息过长，请缩短标题或减小标题字号。');
    }
    lyrics = track.lyrics
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    pages = paginate(
      lyrics.isEmpty ? '把喜欢的句子\n留在这一页' : lyrics,
      style: lyricStyle,
      width: textWidth,
      firstPageHeight: lyricHeight,
      height: size.height - continuationTop - 85,
      maxLines: maxLinesPerPage,
    );
  }

  final String title, artist, album, coverUrl, layout;
  final Size size;
  final Color background, accent;
  final double overlay;
  final Uint8List? backgroundImage;
  final Offset backgroundOffset;
  final double backgroundScale;
  final List<PosterSticker> stickers;
  final bool showPageNumbers, useAlbumCover;
  final String fontFamily;
  final int maxLinesPerPage;

  /// Null retains the album-based default; an empty string hides the text.
  final String? topWatermark;
  final String bottomWatermark;
  final bool showTopWatermark, showBottomWatermark, showTopDecoration;
  String get resolvedTopWatermark =>
      topWatermark ?? 'LYRIC / ${album.toUpperCase()}';
  bool get hasBackgroundImage =>
      backgroundImage != null || (useAlbumCover && coverUrl.isNotEmpty);
  Color get foreground => background.computeLuminance() > .45
      ? const Color(0xFF202124)
      : Colors.white;
  Color get readableAccent {
    final fg = accent.computeLuminance();
    final bg = background.computeLuminance();
    final contrast = (fg > bg
        ? (fg + .05) / (bg + .05)
        : (bg + .05) / (fg + .05));
    return contrast >= 3 ? accent : Color.lerp(accent, foreground, .7)!;
  }

  double get continuationTop => (size.width * .1).clamp(30, 65);
  double lyricTopForPage(int page) => page == 0 ? lyricTop : continuationTop;
  double lyricHeightForPage(int page) =>
      size.height - lyricTopForPage(page) - 85;
  late final String lyrics;
  late final List<String> pages;
  late final double horizontalMargin, textWidth;
  late final double titleTop, titleHeight, artistTop, artistHeight;
  late final double lyricTop, lyricHeight;
  late final TextStyle titleStyle, artistStyle, lyricStyle;

  TextAlign get textAlign =>
      layout == '左对齐' ? TextAlign.left : TextAlign.center;

  static Size paperSize(String dimensions) => switch (dimensions) {
    'A5 竖版' => const Size(419.53, 595.28),
    'A5 横版' => const Size(595.28, 419.53),
    'A6 竖版' => const Size(297.64, 419.53),
    'A3 竖版' => const Size(841.89, 1190.55),
    'A3 横版' => const Size(1190.55, 841.89),
    'A4 横版' => const Size(841.89, 595.28),
    'Letter 竖版' => const Size(612, 792),
    'Letter 横版' => const Size(792, 612),
    '16:9 横版' => const Size(960, 540),
    '正方形' => const Size(595.28, 595.28),
    _ => const Size(595.28, 841.89),
  };

  static double measure(String text, TextStyle style, double width) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  /// Find a fitting prefix using actual wrapped text height. Prefer stanza/line
  /// boundaries, but split a very long line if it alone spans multiple pages.
  /// Every source character is retained, including blank lines and repeats.
  static List<String> paginate(
    String text, {
    required TextStyle style,
    required double width,
    required double height,
    double? firstPageHeight,
    int? maxLines,
  }) {
    final pages = <String>[];
    var remaining = text;
    while (remaining.isNotEmpty) {
      final available = pages.isEmpty ? (firstPageHeight ?? height) : height;
      bool fits(String text) {
        final visible = text.trimRight();
        return (maxLines == null ||
                '\n'.allMatches(visible).length < maxLines) &&
            measure(visible, style, width) <= available - 1;
      }

      if (fits(remaining)) {
        pages.add(remaining);
        break;
      }
      final boundaries = <int>[0];
      var offset = 0;
      for (final rune in remaining.runes) {
        offset += rune > 0xFFFF ? 2 : 1;
        boundaries.add(offset);
      }
      var low = 1, high = boundaries.length - 1, best = 0;
      while (low <= high) {
        final middle = (low + high) ~/ 2;
        final prefix = remaining.substring(0, boundaries[middle]);
        if (fits(prefix)) {
          best = boundaries[middle];
          low = middle + 1;
        } else {
          high = middle - 1;
        }
      }
      if (best == 0) throw StateError('当前画布放不下歌词，请减小字号或增大画布。');
      final newline = remaining.lastIndexOf('\n', best - 1);
      if (newline > 0) best = newline + 1;
      pages.add(remaining.substring(0, best));
      remaining = remaining.substring(best);
    }
    return List.unmodifiable(pages.isEmpty ? [''] : pages);
  }
}

/// A fixed-size page used both by the scaled preview and the export capture.
class PosterPage extends StatelessWidget {
  const PosterPage({
    required this.document,
    required this.page,
    this.onElementTap,
    this.onBackgroundScaleStart,
    this.onBackgroundScaleUpdate,
    this.onStickerScaleStart,
    this.onStickerScaleUpdate,
    super.key,
  });
  final PosterDocument document;
  final int page;
  final ValueChanged<PosterElement>? onElementTap;
  final VoidCallback? onBackgroundScaleStart;
  final ValueChanged<ScaleUpdateDetails>? onBackgroundScaleUpdate;
  final ValueChanged<int>? onStickerScaleStart;
  final void Function(int, ScaleUpdateDetails)? onStickerScaleUpdate;

  @override
  Widget build(BuildContext context) {
    final doc = document;
    return SizedBox.fromSize(
      size: doc.size,
      child: DefaultTextStyle(
        style: TextStyle(
          color: doc.foreground,
          fontFamily: doc.fontFamily,
          fontFamilyFallback: chineseFontFallback,
          fontSize: 12,
        ),
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
        ),
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: doc.background)),
            if (doc.backgroundImage != null)
              Positioned.fill(
                child: ClipRect(
                  child: Transform.translate(
                    offset: doc.backgroundOffset,
                    child: Transform.scale(
                      scale: doc.backgroundScale,
                      child: Image.memory(
                        doc.backgroundImage!,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              )
            else if (doc.useAlbumCover && doc.coverUrl.isNotEmpty)
              Positioned.fill(
                child: Image.network(
                  doc.coverUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: onElementTap == null
                    ? null
                    : () => onElementTap!(PosterElement.background),
                onScaleStart: onBackgroundScaleStart == null
                    ? null
                    : (_) => onBackgroundScaleStart!(),
                onScaleUpdate: onBackgroundScaleUpdate,
                child: ColoredBox(
                  color: doc.hasBackgroundImage
                      ? doc.background.withValues(alpha: doc.overlay)
                      : Colors.transparent,
                ),
              ),
            ),
            if (doc.layout == '唱片')
              Positioned(
                right: -doc.size.width * .18,
                top: doc.size.width * .18,
                child: _record(doc.size.width * .54, doc.accent),
              ),
            if (page == 0 &&
                ((doc.showTopWatermark &&
                        doc.resolvedTopWatermark.trim().isNotEmpty) ||
                    doc.showTopDecoration))
              Positioned(
                top: doc.size.width * .075,
                left: doc.horizontalMargin,
                right: doc.horizontalMargin,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onElementTap == null
                      ? null
                      : () => onElementTap!(PosterElement.topWatermark),
                  child: Row(
                    children: [
                      if (doc.showTopWatermark &&
                          doc.resolvedTopWatermark.trim().isNotEmpty)
                        Expanded(
                          child: Text(
                            doc.resolvedTopWatermark,
                            key: const ValueKey('poster-top-watermark'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: doc.readableAccent.withValues(alpha: .8),
                              fontSize: 12,
                              letterSpacing: 1.3,
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      if (doc.showTopDecoration)
                        Icon(
                          Icons.graphic_eq,
                          key: const ValueKey('poster-top-decoration'),
                          color: doc.readableAccent,
                          size: 24,
                        ),
                    ],
                  ),
                ),
              ),
            if (page == 0)
              Positioned(
                top: doc.titleTop,
                left: doc.horizontalMargin,
                width: doc.textWidth,
                child: GestureDetector(
                  onTap: onElementTap == null
                      ? null
                      : () => onElementTap!(PosterElement.title),
                  child: Text(
                    doc.title,
                    textAlign: doc.textAlign,
                    style: doc.titleStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            if (page == 0)
              Positioned(
                top: doc.artistTop,
                left: doc.horizontalMargin,
                width: doc.textWidth,
                child: GestureDetector(
                  onTap: onElementTap == null
                      ? null
                      : () => onElementTap!(PosterElement.artist),
                  child: Text(
                    doc.artist,
                    textAlign: doc.textAlign,
                    style: doc.artistStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            Positioned(
              top: doc.lyricTopForPage(page),
              left: doc.horizontalMargin,
              width: doc.textWidth,
              height: doc.lyricHeightForPage(page),
              child: GestureDetector(
                onTap: onElementTap == null
                    ? null
                    : () => onElementTap!(PosterElement.lyrics),
                child: Align(
                  alignment: doc.layout == '左对齐'
                      ? Alignment.centerLeft
                      : Alignment.center,
                  child: Text(
                    doc.pages[page].trimRight(),
                    key: const ValueKey('poster-lyrics'),
                    textAlign: doc.textAlign,
                    style: doc.lyricStyle,
                    textScaler: TextScaler.noScaling,
                  ),
                ),
              ),
            ),
            for (var index = 0; index < doc.stickers.length; index++)
              _sticker(doc.stickers[index], index),
            Positioned(
              bottom: 36,
              left: doc.horizontalMargin,
              right: doc.horizontalMargin,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child:
                        doc.showBottomWatermark &&
                            doc.bottomWatermark.trim().isNotEmpty
                        ? GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onElementTap == null
                                ? null
                                : () => onElementTap!(
                                    PosterElement.bottomWatermark,
                                  ),
                            child: Text(
                              doc.bottomWatermark,
                              key: const ValueKey('poster-bottom-watermark'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: doc.foreground.withValues(alpha: .55),
                                fontSize: 11,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (doc.showPageNumbers) const SizedBox(width: 12),
                  if (doc.showPageNumbers)
                    Text(
                      '${page + 1} / ${doc.pages.length}',
                      style: TextStyle(color: doc.readableAccent, fontSize: 12),
                    )
                  else
                    const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sticker(PosterSticker sticker, int index) => Positioned(
    left: sticker.position.dx,
    top: sticker.position.dy,
    child: GestureDetector(
      onTap: onElementTap == null
          ? null
          : () => onElementTap!(PosterElement.sticker),
      onScaleStart: onStickerScaleStart == null
          ? null
          : (_) => onStickerScaleStart!(index),
      onScaleUpdate: onStickerScaleUpdate == null
          ? null
          : (details) => onStickerScaleUpdate!(index, details),
      child: Transform.rotate(
        angle: sticker.rotation,
        child: Image.memory(
          sticker.bytes,
          width: sticker.size * sticker.scale,
          height: sticker.size * sticker.scale,
          fit: BoxFit.contain,
        ),
      ),
    ),
  );

  Widget _record(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.black87,
      border: Border.all(color: color.withValues(alpha: .35), width: 3),
    ),
    child: Center(
      child: Container(
        width: size * .23,
        height: size * .23,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: Colors.white24, width: 2),
        ),
      ),
    ),
  );
}

enum PosterElement {
  background,
  title,
  artist,
  lyrics,
  sticker,
  topWatermark,
  bottomWatermark,
}

class PosterSticker {
  PosterSticker({
    required this.bytes,
    required this.position,
    this.size = 120,
    this.scale = 1,
    this.rotation = 0,
  });

  final Uint8List bytes;
  Offset position;
  double size;
  double scale;
  double rotation;
}
