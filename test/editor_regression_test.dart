import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_poster/color_picker.dart';
import 'package:lyric_poster/editor_fields.dart';
import 'package:lyric_poster/font_library.dart';
import 'package:lyric_poster/history_store.dart';
import 'package:lyric_poster/history_storage.dart';
import 'package:lyric_poster/history_storage_io.dart';
import 'package:lyric_poster/main.dart';
import 'package:lyric_poster/poster_document.dart';
import 'package:lyric_poster/poster_renderer.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestFontDirectory extends PathProviderPlatform {
  TestFontDirectory(this.path);
  final String path;
  @override
  Future<String> getApplicationSupportPath() async => path;
}

class MemoryHistoryStorage implements HistoryStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> remove(String key) async => values.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List fontBytes;
  setUpAll(() async {
    fontBytes = (await rootBundle.load(
      'assets/fonts/NotoSansSC.ttf',
    )).buffer.asUint8List();
    FontLibrary.validateFont(fontBytes);
    final loader = FontLoader(defaultFontFamily)
      ..addFont(Future.value(ByteData.sublistView(fontBytes)));
    await loader.load();
    final appFont = FontLoader(appFontFamily)
      ..addFont(rootBundle.load('assets/fonts/ChillRoundF.ttf'));
    await appFont.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: '词笺',
      packageName: 'com.lyricposter.lyric_poster',
      version: '1.5.4',
      buildNumber: '12',
      buildSignature: '',
    );
  });

  PosterController sample({HistoryStore? history}) {
    final controller = PosterController(history: history);
    controller.selected = Track(
      id: '',
      title: '风与远方',
      artist: '示例歌手',
      album: '时光手记',
      coverUrl: '',
      lyrics: List.generate(25, (i) => '第 ${i + 1} 行：把喜欢的句子，留在这一页。').join('\n'),
    );
    return controller;
  }

  test('默认白纸配深色文字，专辑封面不会覆盖默认白纸', () {
    final controller = sample();
    addTearDown(controller.dispose);
    controller.selected!.coverUrl = 'https://example.com/cover.jpg';
    expect(controller.background, Colors.white);
    expect(controller.defaultBackground, Colors.white);
    expect(controller.document!.hasBackgroundImage, isFalse);
    expect(
      controller.document!.lyricStyle.color!.computeLuminance(),
      lessThan(.1),
    );
    controller.setBackground(Colors.black);
    expect(
      controller.document!.lyricStyle.color!.computeLuminance(),
      greaterThan(.9),
    );
  });

  test('界面使用寒蝉全圆体，已有海报的字体和打印版式保持独立', () {
    final controller = sample();
    addTearDown(controller.dispose);
    expect(controller.appTheme.textTheme.bodyMedium!.fontFamily, appFontFamily);
    expect(appFontFamily, 'ChillRound');
    expect(controller.fonts.selectedFamily, defaultFontFamily);
    expect(controller.document!.lyricStyle.fontFamily, defaultFontFamily);
    expect(controller.document!.titleStyle.fontFamily, defaultFontFamily);
  });

  test('旧版未改动的背景迁移到白色，用户自定义颜色保留', () async {
    for (final color in [0xFF17151F, 0xFFE1EBD6]) {
      SharedPreferences.setMockInitialValues({'defaultBackground': color});
      final controller = PosterController();
      await controller.loadPreferences();
      expect(
        controller.background,
        color == 0xFF17151F ? Colors.white : const Color(0xFFE1EBD6),
      );
      controller.dispose();
    }
  });

  test('每页歌词行数偏好在重启后保留', () async {
    final storage = MemoryHistoryStorage();
    final first = PosterController(history: HistoryStore(storage: storage));
    await first.setMaxLinesPerPage(32);
    first.dispose();

    final restored = PosterController(history: HistoryStore(storage: storage));
    await restored.loadPreferences();
    expect(restored.maxLinesPerPage, 32);
    restored.dispose();
  });

  test('不同纸张与自定义字体字号不会裁掉换行歌词', () {
    final controller = sample();
    addTearDown(controller.dispose);
    for (final paper in PosterController.paperSizes) {
      controller.setDimensions(paper);
      controller.setLyricSize(24);
      final doc = controller.document!;
      expect(doc.pages.join(), controller.selected!.lyrics, reason: paper);
      for (var page = 0; page < doc.pages.length; page++) {
        expect(
          PosterDocument.measure(
            doc.pages[page].trimRight(),
            doc.lyricStyle,
            doc.textWidth,
          ),
          lessThanOrEqualTo(doc.lyricHeightForPage(page)),
          reason: '$paper, page $page',
        );
      }
    }
  });

  test('字体导入会验证完整文件并在重启后恢复选择', () async {
    final temp = await Directory.systemTemp.createTemp('poster-font-test-');
    final original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = TestFontDirectory(temp.path);
    try {
      final first = FontLibrary();
      await first.importFont('自定义中文.ttf', fontBytes);
      final family = first.selectedFamily;
      expect(first.selectedName, '自定义中文');
      first.dispose();
      final second = FontLibrary();
      await second.restore();
      expect(second.selectedFamily, family);
      expect(second.fonts.single.name, '自定义中文');
      await second.select(defaultFontFamily);
      expect(second.selectedFamily, defaultFontFamily);
      second.dispose();
      expect(
        () => FontLibrary.validateFont(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
      expect(
        () =>
            FontLibrary.validateFont(Uint8List.sublistView(fontBytes, 0, 2000)),
        throwsFormatException,
      );
    } finally {
      PathProviderPlatform.instance = original;
      await temp.delete(recursive: true);
    }
  });

  testWidgets('首页欢张使用寒蝉原字体常规字重，双端不触发合成粗体', (tester) async {
    final controller = sample();
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    for (final width in [390.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('font-home-preview'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: controller.appTheme,
            home: PosterWorkspace(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text('把喜欢的歌，做成一张海报。'),
      );
      expect(paragraph.text.style!.fontFamily, appFontFamily);
      expect(paragraph.text.style!.fontWeight, FontWeight.w400);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('WRITE_PREVIEWS')) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('font-home-preview')),
          );
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('work/previews').create(recursive: true);
          await File(
            'work/previews/font-home-${width.toInt()}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
  });

  testWidgets('寒蝉全圆体在Flutter中的常规与合成粗体字形对照', (tester) async {
    if (!const bool.fromEnvironment('WRITE_PREVIEWS')) return;
    final controller = sample();
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 560);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('font-comparison-preview'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: controller.appTheme,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '同一官方字体 · Flutter 实际渲染',
                    style: TextStyle(fontSize: 22),
                  ),
                  const SizedBox(height: 20),
                  for (final weight in [
                    FontWeight.w400,
                    FontWeight.w600,
                    FontWeight.w800,
                  ]) ...[
                    Text(
                      '字重 ${weight.value}',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '把喜欢的歌，做成一张海报。  欢 张',
                      style: TextStyle(
                        fontFamily: appFontFamily,
                        fontSize: 40,
                        fontWeight: weight,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('font-comparison-preview')),
      );
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('work/previews').create(recursive: true);
      await File(
        'work/previews/font-weight-comparison.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  });

  testWidgets('第一页有标题和歌手，后续页仅有歌词与页脚', (tester) async {
    final controller = sample();
    addTearDown(controller.dispose);
    final doc = controller.document!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FittedBox(child: PosterPage(document: doc, page: 0)),
        ),
      ),
    );
    expect(find.text('风与远方'), findsOneWidget);
    expect(find.text('示例歌手'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FittedBox(child: PosterPage(document: doc, page: 1)),
        ),
      ),
    );
    expect(find.text('风与远方'), findsNothing);
    expect(find.text('示例歌手'), findsNothing);
    expect(find.textContaining('LYRIC /'), findsNothing);
    expect(find.byKey(const ValueKey('poster-lyrics')), findsOneWidget);
    expect(doc.lyricTopForPage(1), lessThan(doc.lyricTopForPage(0)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('调色盘可拖动、选预设并验证 HEX', (tester) async {
    Color? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showColorPalette(context, Colors.white);
              },
              child: const Text('打开调色盘'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开调色盘'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('color-hue')),
      const Offset(60, 0),
    );
    await tester.drag(
      find.byKey(const ValueKey('color-sv')),
      const Offset(-20, 25),
    );
    await tester.ensureVisible(find.byTooltip('薄荷 · #D6F1E7'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('薄荷 · #D6F1E7'));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('color-hex')))
          .controller!
          .text,
      'D6F1E7',
    );
    await tester.enterText(find.byKey(const ValueKey('color-hex')), 'error');
    await tester.tap(find.text('应用'));
    await tester.pump();
    expect(find.text('请输入 6 位十六进制颜色'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('color-hex')), 'EDE2FA');
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(selected, const Color(0xFFEDE2FA));
  });

  for (final width in [320.0, 390.0, 980.0, 1280.0]) {
    for (final tab in [0, 1, 2, 3, 4, 5]) {
      testWidgets('六页导航布局 ${width.toInt()}px / tab$tab 不溢出，仅歌单页显示我的音乐', (
        tester,
      ) async {
        final controller = sample();
        controller.tracks.add(controller.selected!);
        addTearDown(controller.dispose);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        controller.setTab(tab);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-scene'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: controller.appTheme,
              home: PosterWorkspace(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('我的音乐'),
          tab == 0 ? findsOneWidget : findsNothing,
          reason: '$width, tab $tab',
        );
        expect(
          find.byKey(const ValueKey('design-sidebar')),
          tab == 1 ? findsOneWidget : findsNothing,
        );
        if (width >= 980) {
          expect(
            tester
                .widget<NavigationRail>(find.byType(NavigationRail))
                .selectedIndex,
            tab,
          );
          expect(find.byType(NavigationBar), findsNothing);
        } else {
          expect(
            tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .selectedIndex,
            tab,
          );
          expect(find.byType(NavigationRail), findsNothing);
        }
        if (tab == 3) expect(find.text('历史记录'), findsOneWidget);
        if (tab == 4) expect(find.text('导入字体'), findsOneWidget);
        if (tab == 5) expect(find.text('关于词笺'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$width, tab $tab');
        if (const bool.fromEnvironment('WRITE_PREVIEWS') &&
            (width == 390 || width == 1280) &&
            (tab == 1 || tab == 5)) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('workspace-scene')),
            );
            final image = await boundary.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory('work/previews').create(recursive: true);
            await File(
              'work/previews/workspace-${width.toInt()}-$tab.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }

  testWidgets('动画进行中快速切换设计和导出始终只有一份海报预览', (tester) async {
    final controller = sample()..setTab(1);
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpWidget(
      MaterialApp(
        theme: controller.appTheme,
        home: PosterWorkspace(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    for (final tab in [2, 1, 2, 1, 2, 1]) {
      controller.setTab(tab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));
      expect(find.byType(PosterCanvas), findsOneWidget);
      expect(find.byKey(const ValueKey('poster-lyrics')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '切换到 tab$tab');
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('design-sidebar')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('调整字号和拖动背景时海报立即更新且不会重新淡出', (tester) async {
    final controller = sample()..setTab(1);
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpWidget(
      MaterialApp(
        theme: controller.appTheme,
        home: PosterWorkspace(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    void expectFullyVisible() {
      for (final name in [
        'workspace-motion',
        'editor-motion',
        'preview-motion',
      ]) {
        final fade = find.descendant(
          of: find.byKey(ValueKey(name)),
          matching: find.byType(FadeTransition),
        );
        expect(tester.widget<FadeTransition>(fade.first).opacity.value, 1);
      }
    }

    controller.setLyricSize(16);
    await tester.pump();
    expect(controller.document!.lyricStyle.fontSize, 16);
    expectFullyVisible();
    controller.moveBackground(const Offset(12, -8));
    controller.scaleBackground(1.15);
    await tester.pump();
    expect(controller.backgroundOffset, const Offset(12, -8));
    expect(controller.backgroundScale, 1.15);
    expectFullyVisible();
    controller.updateSelected(title: '更新后的标题');
    await tester.pump();
    expect(find.text('更新后的标题'), findsOneWidget);
    expectFullyVisible();
    expect(tester.takeException(), isNull);
  });

  testWidgets('独立导出是固定300DPI且不改变当前歌词页', (tester) async {
    final controller = sample();
    addTearDown(controller.dispose);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(home: Scaffold(key: key)));
    final doc = controller.document!;
    final outputs = <Uint8List>[];
    await tester.runAsync(() async {
      for (var page = 0; page < doc.pages.length; page++) {
        outputs.add(
          await renderPosterPage(doc, page, context: key.currentContext!),
        );
      }
      final codec = await ui.instantiateImageCodec(outputs.first);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, (doc.size.width * 300 / 72).ceil());
      expect(frame.image.height, (doc.size.height * 300 / 72).ceil());
      frame.image.dispose();
      codec.dispose();
      if (const bool.fromEnvironment('WRITE_PREVIEWS')) {
        final directory = await Directory(
          'work/previews',
        ).create(recursive: true);
        for (var i = 0; i < outputs.length; i++) {
          await File(
            '${directory.path}/poster-${i + 1}.png',
          ).writeAsBytes(outputs[i]);
        }
      }
    });
    expect(controller.lyricPage, 0);
    expect(outputs.length, doc.pages.length);
    expect(tester.takeException(), isNull);
  });

  testWidgets('页面动画进行中导出的海报像素与静止时一致', (tester) async {
    final controller = sample()..setTab(1);
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpWidget(
      MaterialApp(
        theme: controller.appTheme,
        home: PosterWorkspace(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(PosterWorkspace));
    final document = controller.document!;
    late Uint8List baseline;
    await tester.runAsync(() async {
      baseline = await renderPosterPage(document, 0, context: context, dpi: 72);
    });
    controller.setTab(2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 35));
    await tester.runAsync(() async {
      final duringMotion = await renderPosterPage(
        document,
        0,
        context: context,
        dpi: 72,
      );
      expect(duringMotion, orderedEquals(baseline));
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('独立渲染包含自定义背景图和贴纸', (tester) async {
    final controller = sample();
    addTearDown(controller.dispose);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(home: Scaffold(key: key)));
    await tester.runAsync(() async {
      Future<Uint8List> tile(Color color) async {
        final recorder = ui.PictureRecorder();
        Canvas(
          recorder,
        ).drawRect(const Rect.fromLTWH(0, 0, 20, 20), Paint()..color = color);
        final picture = recorder.endRecording();
        final image = await picture.toImage(20, 20);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return data!.buffer.asUint8List();
      }

      controller.setOverlay(0);
      controller.setBackgroundImage(
        await tile(const Color(0xFF00AA55)),
        '背景.png',
      );
      controller.addSticker(await tile(const Color(0xFF3355FF)));
      controller.stickers.single.position = const Offset(10, 10);
      final bytes = await renderPosterPage(
        controller.document!,
        0,
        context: key.currentContext!,
        dpi: 72,
      );
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      Color pixel(int x, int y) {
        final offset = (y * image.width + x) * 4;
        return Color.fromARGB(
          raw!.getUint8(offset + 3),
          raw.getUint8(offset),
          raw.getUint8(offset + 1),
          raw.getUint8(offset + 2),
        );
      }

      expect(pixel(4, 4), const Color(0xFF00AA55));
      expect(pixel(20, 20), const Color(0xFF3355FF));
      image.dispose();
      codec.dispose();
    });
    expect(tester.takeException(), isNull);
  });

  test('歌单和海报草稿历史会持久化并还原图片字节', () async {
    final storage = MemoryHistoryStorage();
    final first = HistoryStore(storage: storage);
    final track = Track(
      id: '42',
      title: '风与远方',
      artist: '示例歌手',
      album: '时光手记',
      coverUrl: 'https://example.com/cover.jpg',
      lyrics: '第一句\n第二句',
      durationMs: 1234,
    );
    await first.savePlaylist('123456', '我的歌单', [track]);
    final image = Uint8List.fromList([1, 2, 3, 255]);
    await first.saveDraft('draft-1', {
      'track': trackToMap(track),
      'dimensions': 'A4 竖版',
      'backgroundImage': image,
      'stickers': [
        {'bytes': image},
      ],
    });

    final restored = HistoryStore(storage: storage);
    await restored.load();
    expect(restored.playlists.single.trackCount, 1);
    final playlist = await restored.readEntry(restored.playlists.single.id);
    expect(
      trackFromMap(
        Map<String, dynamic>.from((playlist['tracks'] as List).single as Map),
      ).lyrics,
      track.lyrics,
    );
    final draft = await restored.readEntry(restored.drafts.single.id);
    expect(draft['backgroundImage'], image);
    expect(((draft['stickers'] as List).single as Map)['bytes'], image);

    await restored.delete(restored.playlists.single, playlist: true);
    expect(restored.playlists, isEmpty);
    expect(restored.drafts, hasLength(1));
    first.dispose();
    restored.dispose();
  });

  test('Windows 本机历史文件可安全重复更新和删除', () async {
    final temp = await Directory.systemTemp.createTemp('poster-history-test-');
    final original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = TestFontDirectory(temp.path);
    final store = HistoryStore(storage: LocalHistoryStorage());
    try {
      await store.savePlaylist('123456', '第一次', [
        Track(id: '1', title: '旧歌', artist: '歌手', album: '', coverUrl: ''),
      ]);
      await store.savePlaylist('123456', '第二次', [
        Track(id: '2', title: '新歌', artist: '歌手', album: '', coverUrl: ''),
      ]);
      final restored = HistoryStore(storage: LocalHistoryStorage());
      await restored.load();
      expect(restored.playlists.single.title, '第二次');
      final payload = await restored.readEntry(restored.playlists.single.id);
      expect((payload['tracks'] as List).single['title'], '新歌');
      await restored.delete(restored.playlists.single, playlist: true);
      expect(restored.playlists, isEmpty);
      restored.dispose();
    } finally {
      store.dispose();
      PathProviderPlatform.instance = original;
      await temp.delete(recursive: true);
    }
  });

  test('打开草稿恢复歌曲、版式、分页和完整装饰', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = MemoryHistoryStorage();
    final history = HistoryStore(storage: storage);
    final controller = sample();
    final sampleTrack = controller.selected!;
    controller.dispose();
    final editing = PosterController(history: history);
    editing.historyReady = true;
    editing.selected = sampleTrack;
    editing.setDimensions('A5 横版');
    editing.setBackground(const Color(0xFFE1EBD6));
    editing.setLyricSize(20);
    await editing.setMaxLinesPerPage(30);
    editing.setBackgroundImage(Uint8List.fromList([8, 9]), '背景.png');
    editing.addSticker(Uint8List.fromList([3, 4]));
    await editing.saveDraft();
    final entry = history.drafts.single;

    editing.selected = Track(
      id: 'other',
      title: '另一首',
      artist: '其他歌手',
      album: '',
      coverUrl: '',
    );
    editing.activeDraftId = null;
    editing.draftDirty = false;
    await editing.openDraft(entry);
    expect(editing.selected!.title, '风与远方');
    expect(editing.dimensions, 'A5 横版');
    expect(editing.background, const Color(0xFFE1EBD6));
    expect(editing.lyricSize, 20);
    expect(editing.maxLinesPerPage, 30);
    expect(editing.backgroundImage, [8, 9]);
    expect(editing.stickers.single.bytes, [3, 4]);
    expect(editing.draftDirty, isFalse);
    editing.dispose();
  });

  testWidgets('设计页适应可视区域，无需滚动即可看到整张海报', (tester) async {
    final controller = sample();
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    controller.setTab(1);
    await tester.pumpWidget(
      MaterialApp(
        theme: controller.appTheme,
        home: PosterWorkspace(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('poster-lyrics')), findsOneWidget);
    expect(find.text('排版与纸张'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('历史页可在手机导航打开并显示空状态', (tester) async {
    final controller = sample();
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    controller.setTab(3);
    await tester.pumpWidget(
      MaterialApp(
        theme: controller.appTheme,
        home: PosterWorkspace(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('历史记录'), findsOneWidget);
    expect(find.textContaining('还没有海报草稿'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('排版工具提供每页行数滑块并更新预览', (tester) async {
    final controller = sample();
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    controller.setTab(1);
    await tester.pumpWidget(
      MaterialApp(
        theme: controller.appTheme,
        home: PosterWorkspace(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('排版与纸张'));
    await tester.pumpAndSettle();
    final slider = find.byKey(const ValueKey('max-lines-per-page'));
    expect(slider, findsOneWidget);
    expect(tester.widget<Slider>(slider).value, 24);
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.drag(slider, const Offset(70, 0));
    await tester.pumpAndSettle();
    expect(controller.maxLinesPerPage, greaterThan(24));
    expect(tester.takeException(), isNull);
  });

  testWidgets('固定侧栏与海报并排，点击标题和水印切换工具且不弹窗', (tester) async {
    final controller = sample()..setTab(1);
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpWidget(
      MaterialApp(
        theme: controller.appTheme,
        home: PosterWorkspace(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    final sidebar = find.byKey(const ValueKey('design-sidebar'));
    final poster = find.byType(PosterCanvas);
    expect(
      tester.getRect(sidebar).left,
      greaterThanOrEqualTo(tester.getRect(poster).right),
    );
    await tester.tap(find.text('风与远方'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-song-title')), findsOneWidget);
    expect(find.text('海报字体'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.byKey(const ValueKey('poster-top-watermark')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-top-watermark')), findsOneWidget);
    expect(sidebar, findsOneWidget);
    expect(find.byKey(const ValueKey('poster-lyrics')), findsOneWidget);
    await tester.tap(find.byTooltip('收起设计侧栏'));
    await tester.pumpAndSettle();
    expect(sidebar, findsNothing);
    await tester.tap(find.byTooltip('展开设计侧栏'));
    await tester.pumpAndSettle();
    expect(sidebar, findsOneWidget);
    expect(find.byKey(const ValueKey('edit-top-watermark')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机短屏及键盘弹出时工具和海报预览仍有空间且不溢出', (tester) async {
    final controller = sample()..setTab(1);
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    tester.view.devicePixelRatio = 1;
    for (final (height, keyboard) in [(520.0, 0.0), (800.0, 300.0)]) {
      tester.view.physicalSize = Size(390, height);
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      await tester.pumpWidget(
        MaterialApp(
          theme: controller.appTheme,
          home: PosterWorkspace(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      final sidebar = find.byKey(const ValueKey('design-sidebar'));
      final poster = find.byType(PosterCanvas);
      expect(sidebar, findsOneWidget);
      expect(poster, findsOneWidget);
      expect(tester.getRect(poster).height, greaterThan(0));
      expect(
        tester.getRect(poster).bottom,
        lessThanOrEqualTo(tester.getRect(sidebar).top),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'height $height keyboard $keyboard',
      );
    }
  });

  for (final width in [390.0, 1280.0, 1920.0]) {
    testWidgets('设计分组 ${width.toInt()}px 完整显示并可直接点击最右侧水印按钮', (tester) async {
      final controller = sample()..setTab(1);
      addTearDown(controller.dispose);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(
        MaterialApp(
          theme: controller.appTheme,
          home: PosterWorkspace(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      final sidebar = find.byKey(const ValueKey('design-sidebar'));
      expect(find.byKey(const ValueKey('editor-sections')), findsOneWidget);
      for (final section in ['排版与纸张', '文字与字体', '背景与颜色', '图片与贴纸', '上下水印']) {
        final button = find.byKey(ValueKey('editor-section-$section'));
        final bounds = tester.getRect(sidebar);
        final rect = tester.getRect(button);
        expect(rect.left, greaterThanOrEqualTo(bounds.left));
        expect(rect.top, greaterThanOrEqualTo(bounds.top));
        expect(rect.right, lessThanOrEqualTo(bounds.right));
        expect(rect.bottom, lessThanOrEqualTo(bounds.bottom));
        expect(button.hitTestable(), findsOneWidget);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(tester.widget<ChoiceChip>(button).selected, isTrue);
        expect(tester.takeException(), isNull, reason: '$width / $section');
      }
      expect(find.byKey(const ValueKey('edit-top-watermark')), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });
  }

  testWidgets('短屏和键盘展开时可通过紧凑分组切换到最后一项', (tester) async {
    final controller = sample()..setTab(1);
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    tester.view.devicePixelRatio = 1;
    for (final (height, keyboard) in [(520.0, 0.0), (800.0, 300.0)]) {
      tester.view.physicalSize = Size(390, height);
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      await tester.pumpWidget(
        MaterialApp(
          theme: controller.appTheme,
          home: PosterWorkspace(
            key: ValueKey('compact-$height-$keyboard'),
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final groupMenu = find.byKey(const ValueKey('compact-editor-sections'));
      expect(groupMenu.hitTestable(), findsOneWidget);
      await tester.tap(groupMenu);
      await tester.pumpAndSettle();
      final lastSection = find.text('上下水印').hitTestable();
      expect(lastSection, findsOneWidget);
      await tester.tap(lastSection);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edit-top-watermark')), findsOneWidget);
      expect(tester.getRect(find.byType(PosterCanvas)).height, greaterThan(0));
      expect(
        tester.takeException(),
        isNull,
        reason: 'height $height keyboard $keyboard',
      );
    }
  });

  testWidgets('打印字号精确接受小数，非法输入保留文字且不改变版式', (tester) async {
    final controller = sample();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => Column(
              children: [
                PointSizeField(
                  key: const ValueKey('test-title-size'),
                  label: '标题字号',
                  value: controller.titleSize,
                  max: 144,
                  onChanged: controller.setTitleSize,
                ),
                PointSizeField(
                  key: const ValueKey('test-lyric-size'),
                  label: '歌词字号',
                  value: controller.lyricSize,
                  max: 96,
                  onChanged: controller.setLyricSize,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Finder field(String key) => find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(TextField),
    );
    final title = field('test-title-size');
    final lyrics = field('test-lyric-size');
    await tester.enterText(title, '31.25');
    await tester.pump();
    await tester.enterText(lyrics, '16.75');
    await tester.pump();
    expect(controller.titleSize, 31.25);
    expect(controller.lyricSize, 16.75);
    expect(controller.document!.lyricStyle.fontSize, 16.75);
    for (final input in [
      '',
      '.',
      'abc',
      'NaN',
      'Infinity',
      '-2',
      '3.99',
      '96.01',
    ]) {
      await tester.enterText(lyrics, input);
      await tester.pump();
      expect(controller.lyricSize, 16.75, reason: input);
      expect(tester.widget<TextField>(lyrics).controller!.text, input);
      expect(find.text('请输入 4–96 的数值'), findsOneWidget);
    }
    await tester.enterText(title, '144.01');
    await tester.pump();
    expect(controller.titleSize, 31.25);
    expect(find.text('请输入 4–144 的数值'), findsOneWidget);
    await tester.enterText(lyrics, '17.5');
    await tester.pump();
    expect(controller.lyricSize, 17.5);
    expect(find.text('请输入 4–96 的数值'), findsNothing);
    controller.setLyricSize(19.25);
    await tester.pump();
    expect(tester.widget<TextField>(lyrics).controller!.text, '19.25');
    expect(tester.takeException(), isNull);
  });

  test('水印与精确字号保存到草稿，重启后恢复并兼容旧版草稿', () async {
    final storage = MemoryHistoryStorage();
    final firstHistory = HistoryStore(storage: storage);
    final first = sample(history: firstHistory)..historyReady = true;
    addTearDown(first.dispose);
    first.updateWatermarks(
      top: '自写诗句 · 测试页眉',
      bottom: '私人手记 · 测试页脚',
      showTop: false,
      showBottom: true,
      decoration: false,
    );
    expect(first.setTitleSize(31.25), isTrue);
    expect(first.setLyricSize(16.75), isTrue);
    await first.saveDraft();
    final entry = firstHistory.drafts.single;
    final restoredHistory = HistoryStore(storage: storage);
    final restored = PosterController(history: restoredHistory);
    addTearDown(restored.dispose);
    await restoredHistory.load();
    await restored.openDraft(restoredHistory.drafts.single);
    expect(restored.topWatermark, '自写诗句 · 测试页眉');
    expect(restored.bottomWatermark, '私人手记 · 测试页脚');
    expect(restored.showTopWatermark, isFalse);
    expect(restored.showBottomWatermark, isTrue);
    expect(restored.showTopDecoration, isFalse);
    expect(restored.titleSize, 31.25);
    expect(restored.lyricSize, 16.75);
    expect(restored.document!.bottomWatermark, '私人手记 · 测试页脚');
    expect(restored.draftDirty, isFalse);
    final legacy = await firstHistory.readEntry(entry.id);
    for (final field in [
      'topWatermark',
      'bottomWatermark',
      'showTopWatermark',
      'showBottomWatermark',
      'showTopDecoration',
    ]) {
      legacy.remove(field);
    }
    await firstHistory.saveDraft('draft-1', legacy);
    await restored.openDraft(
      firstHistory.drafts.firstWhere((item) => item.id == 'draft-1'),
    );
    expect(restored.topWatermark, isNull);
    expect(restored.bottomWatermark, '词笺 · LYRIC POSTER');
    expect(restored.showTopWatermark, isTrue);
    expect(restored.showBottomWatermark, isTrue);
    expect(restored.showTopDecoration, isTrue);
  });
}
