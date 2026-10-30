import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_poster/font_library.dart';
import 'package:lyric_poster/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      appFontFamily,
    )..addFont(rootBundle.load('assets/fonts/ChillRoundF.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in [320.0, 390.0, 980.0, 1280.0, 1920.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('首页功能卡片等宽等高且设置仍可从导航访问 $width / $scale', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 990);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = PosterController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('home-feedback-preview'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: controller.appTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: PosterWorkspace(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byIcon(Icons.settings_outlined),
          ),
          findsNothing,
        );
        final cards = ['搜索单曲', '画布直编', '适合打印']
            .map(
              (title) => tester.getRect(
                find.ancestor(
                  of: find.text(title),
                  matching: find.byType(Card),
                ),
              ),
            )
            .toList();
        for (final card in cards.skip(1)) {
          expect(card.width, closeTo(cards.first.width, .01));
          expect(card.height, closeTo(cards.first.height, .01));
          expect(card.top, closeTo(cards.first.top, .01));
          expect(card.bottom, closeTo(cards.first.bottom, .01));
        }
        expect(tester.takeException(), isNull);

        if (const bool.fromEnvironment('WRITE_PREVIEWS') &&
            scale == 1 &&
            (width == 390 || width == 1280 || width == 1920)) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('home-feedback-preview')),
            );
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory('work/previews').create(recursive: true);
            await File(
              'work/previews/home-156-${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await tester.tap(find.text('设置'));
        await tester.pumpAndSettle();
        expect(controller.currentTab, 4);
        expect(find.text('导入字体'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
