import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_poster/app_updates.dart';
import 'package:lyric_poster/main.dart';

void main() {
  testWidgets('歌曲列表滚动时选中背景不会绘制到搜索和歌单信息区', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PosterController();
    addTearDown(controller.dispose);
    controller.tracks.addAll(
      List.generate(
        30,
        (index) => Track(
          id: '$index',
          title: '歌曲 $index',
          artist: '歌手',
          album: '',
          coverUrl: '',
          lyrics: '歌词',
        ),
      ),
    );
    controller.selected = controller.tracks.first;
    const boundaryKey = ValueKey('library-scroll-preview');
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          theme: controller.appTheme,
          home: PosterWorkspace(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byType(ListView).first;
    final listRect = tester.getRect(list);
    final header = Rect.fromLTRB(
      listRect.left,
      tester.getRect(find.text('我的音乐')).top,
      listRect.right,
      listRect.top,
    );
    Future<List<int>> headerPixels() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final image = await boundary.toImage();
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final bytes = data.buffer.asUint8List();
      final result = <int>[];
      for (var y = header.top.ceil(); y < header.bottom.floor(); y++) {
        result.addAll(
          bytes.sublist(
            (y * image.width + header.left.ceil()) * 4,
            (y * image.width + header.right.floor()) * 4,
          ),
        );
      }
      image.dispose();
      return result;
    }

    final before = (await tester.runAsync(headerPixels))!;
    await tester.drag(list, const Offset(0, -240));
    await tester.pumpAndSettle();
    final after = (await tester.runAsync(headerPixels))!;
    final differences = after.indexed.where(
      (pixel) => before[pixel.$1] != pixel.$2,
    );
    expect(differences.length, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('各页面均不显示重复的顶部导出海报按钮', (tester) async {
    final controller = PosterController();
    final updates = UpdateController(
      versionLoader: () async =>
          const InstalledVersion(version: '1.5.7', buildNumber: '15'),
    );
    addTearDown(controller.dispose);
    addTearDown(updates.dispose);
    controller.selected = Track(
      id: '',
      title: '歌曲',
      artist: '歌手',
      album: '',
      coverUrl: '',
      lyrics: '歌词',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PosterWorkspace(controller: controller, updates: updates),
      ),
    );
    for (final tab in [0, 1, 2, 3, 4, 5]) {
      controller.setTab(tab);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('导出海报')),
        findsNothing,
      );
      if (tab == 2) {
        expect(find.text('导出当前页 PNG'), findsOneWidget);
        expect(find.text('导出全部 PDF'), findsOneWidget);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
