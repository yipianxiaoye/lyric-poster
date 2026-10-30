import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_poster/font_library.dart';
import 'package:lyric_poster/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecordingFilePicker extends FilePickerPlatform {
  final saves = <({String name, String mimeType, Uint8List bytes})>[];
  Completer<void>? onSaved;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    saves.add((name: fileName, mimeType: mimeType, bytes: bytes));
    onSaved?.complete();
    return Uri.file(fileName);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in {
      defaultFontFamily: 'assets/fonts/NotoSansSC.ttf',
      appFontFamily: 'assets/fonts/ChillRoundF.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final multiPage in [false, true]) {
    testWidgets('保存对话框使用歌曲名，PNG 页码与 PDF 全部页面保持正确 $multiPage', (tester) async {
      final originalPicker = FilePickerPlatform.instance;
      final picker = RecordingFilePicker();
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = originalPicker);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = PosterController()
        ..selected = Track(
          id: '',
          title: '风与远方',
          artist: '歌手',
          album: '专辑',
          coverUrl: '',
          lyrics: multiPage ? '第一行\n第二行\n第三行\n第四行\n第五行' : '把喜欢的句子留在这一页',
        )
        ..dimensions = 'A6 竖版'
        ..maxLinesPerPage = 2
        ..currentTab = 2;
      addTearDown(controller.dispose);
      final expectedPageCount = controller.document!.pages.length;
      expect(expectedPageCount, multiPage ? greaterThan(1) : 1);
      if (multiPage) controller.setLyricPage(1);
      await tester.pumpWidget(
        MaterialApp(
          theme: controller.appTheme,
          home: PosterWorkspace(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      final pngButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('导出当前页 PNG'),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        ),
      );
      await tester.runAsync(() async {
        final pngSaved = Completer<void>();
        picker.onSaved = pngSaved;
        pngButton.onPressed!();
        await pngSaved.future.timeout(const Duration(seconds: 20));
      });
      await tester.pumpAndSettle();
      final png = picker.saves.single;
      expect(png.name, multiPage ? '风与远方-第2页.png' : '风与远方.png');
      expect(png.mimeType, 'image/png');
      expect(png.bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(controller.lyricPage, multiPage ? 1 : 0);

      final pdfButton = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('导出全部 PDF'),
          matching: find.byWidgetPredicate(
            (widget) => widget is OutlinedButton,
          ),
        ),
      );
      await tester.runAsync(() async {
        final pdfSaved = Completer<void>();
        picker.onSaved = pdfSaved;
        pdfButton.onPressed!();
        await pdfSaved.future.timeout(const Duration(seconds: 20));
      });
      await tester.pumpAndSettle();
      final pdf = picker.saves.last;
      expect(pdf.name, '风与远方.pdf');
      expect(pdf.mimeType, 'application/pdf');
      expect(String.fromCharCodes(pdf.bytes.take(4)), '%PDF');
      expect(
        String.fromCharCodes(pdf.bytes),
        contains('/Count $expectedPageCount'),
      );
      expect(picker.saves, hasLength(2));
      expect(controller.lyricPage, multiPage ? 1 : 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
