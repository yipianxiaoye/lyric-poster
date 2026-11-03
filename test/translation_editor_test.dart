import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_poster/font_library.dart';
import 'package:lyric_poster/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const customFont = ImportedFont(id: 'ftesttranslation', name: '测试译文字体');

  setUpAll(() async {
    for (final family in [defaultFontFamily, customFont.family]) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
    }
    await (FontLoader(
      appFontFamily,
    )..addFont(rootBundle.load('assets/fonts/ChillRoundF.ttf'))).load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in [390.0, 1280.0]) {
    testWidgets('双语编辑可独立设置字号与字体并切换译文 $width px', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = PosterController();
      addTearDown(controller.dispose);
      controller.fonts.fonts.add(customFont);
      controller.selected = Track(
        id: '',
        title: 'A quiet song',
        artist: 'Singer',
        album: '',
        coverUrl: '',
        lyrics: 'The sun is rising\nThe world is waking',
        translation: '太阳升起\n世界醒来',
        translationFetched: true,
      );
      controller.currentTab = 1;
      final originalSize = controller.lyricSize;
      final originalFont = controller.fonts.selectedFamily;
      await tester.pumpWidget(
        MaterialApp(
          theme: controller.appTheme,
          home: PosterWorkspace(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      final textSection = find.byKey(const ValueKey('editor-section-文字与字体'));
      await tester.tap(textSection);
      await tester.pumpAndSettle();
      final translationSwitch = find.byKey(const ValueKey('show-translation'));
      expect(translationSwitch, findsOneWidget);
      expect(find.text('译文字体'), findsOneWidget);
      expect(controller.document!.hasTranslation, isTrue);

      final size = find.byKey(const ValueKey('translation-size-input'));
      await tester.ensureVisible(size);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: size, matching: find.byType(TextField)),
        '18.5',
      );
      await tester.pumpAndSettle();
      expect(controller.translationSize, 18.5);
      expect(controller.lyricSize, originalSize);
      expect(controller.document!.translationStyle.fontSize, 18.5);
      expect(controller.document!.lyricStyle.fontSize, originalSize);

      final translationFont = find.byKey(
        ValueKey('translation-font-$originalFont'),
      );
      await tester.ensureVisible(translationFont);
      await tester.pumpAndSettle();
      await tester.tap(translationFont);
      await tester.pumpAndSettle();
      await tester.tap(find.text(customFont.name).last);
      await tester.pumpAndSettle();
      expect(controller.translationFontFamily, customFont.family);
      expect(controller.fonts.selectedFamily, originalFont);
      expect(
        controller.document!.translationStyle.fontFamily,
        customFont.family,
      );
      expect(controller.document!.lyricStyle.fontFamily, originalFont);

      await tester.ensureVisible(translationSwitch);
      await tester.pumpAndSettle();
      await tester.tap(translationSwitch);
      await tester.pumpAndSettle();
      expect(controller.showTranslation, isFalse);
      expect(
        find.byKey(const ValueKey('translation-size-input')),
        findsNothing,
      );
      expect(find.text('译文字体'), findsNothing);
      expect(controller.document!.hasTranslation, isFalse);
      expect(
        controller.document!.pageTextSpan(0).toPlainText(),
        isNot(contains('太阳升起')),
      );

      await tester.tap(translationSwitch);
      await tester.pumpAndSettle();
      expect(controller.showTranslation, isTrue);
      expect(controller.translationSize, 18.5);
      expect(controller.translationFontFamily, customFont.family);
      expect(controller.document!.hasTranslation, isTrue);
      expect(
        controller.document!.pageTextSpan(0).toPlainText(),
        contains('太阳升起'),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
