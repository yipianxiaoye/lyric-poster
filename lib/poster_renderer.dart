import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'poster_document.dart';

/// Renders in paper coordinates, without depending on the preview's viewport,
/// scroll position, display scaling, or selection state.
Future<Uint8List> renderPosterPage(
  PosterDocument document,
  int page, {
  required BuildContext context,
  double dpi = 300,
}) async {
  if (page < 0 || page >= document.pages.length) {
    throw RangeError.index(page, document.pages);
  }
  if (!dpi.isFinite || dpi <= 0) throw ArgumentError.value(dpi, 'dpi');
  if (document.backgroundImage != null) {
    await precacheImage(MemoryImage(document.backgroundImage!), context);
  } else if (document.useAlbumCover && document.coverUrl.isNotEmpty) {
    await precacheImage(
      NetworkImage(document.coverUrl),
      context,
      onError: (_, _) {},
    );
  }
  for (final sticker in document.stickers) {
    if (!context.mounted) throw StateError('导出已取消');
    await precacheImage(MemoryImage(sticker.bytes), context);
  }
  if (!context.mounted) throw StateError('导出已取消');
  final ratio = dpi / 72;
  final boundary = RenderRepaintBoundary();
  final view = RenderView(
    view: View.of(context),
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(document.size),
      physicalConstraints: BoxConstraints.tight(document.size * ratio),
      devicePixelRatio: ratio,
    ),
    child: boundary,
  );
  final pipeline = PipelineOwner()..rootNode = view;
  final focus = FocusManager();
  final owner = BuildOwner(focusManager: focus);
  view.prepareInitialFrame();
  final root = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(
          size: document.size,
          textScaler: TextScaler.noScaling,
        ),
        child: PosterPage(document: document, page: page),
      ),
    ),
  ).attachToRenderTree(owner);
  try {
    owner.buildScope(root);
    owner.finalizeTree();
    pipeline.flushLayout();
    pipeline.flushCompositingBits();
    pipeline.flushPaint();
    final image = await boundary.toImage(pixelRatio: ratio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('无法生成海报图片');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    root.update(RenderObjectToWidgetAdapter<RenderBox>(container: boundary));
    owner.buildScope(root);
    owner.finalizeTree();
    pipeline.rootNode = null;
    view.child = null;
    boundary.dispose();
    view.dispose();
    pipeline.dispose();
    focus.dispose();
  }
}
