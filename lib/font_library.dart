import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show FontWeight, TextTheme;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'font_storage_io.dart'
    if (dart.library.html) 'font_storage_web.dart'
    as storage;

const defaultFontFamily = 'PosterSans';
const appFontFamily = 'ChillRound';

/// ChillRoundF supplies a Regular face only. Synthetic bold distorts some
/// outlines, so interface text uses its native weight at every text size.
TextTheme appTextTheme(TextTheme base) => base.copyWith(
  displayLarge: base.displayLarge?.copyWith(fontWeight: FontWeight.w400),
  displayMedium: base.displayMedium?.copyWith(fontWeight: FontWeight.w400),
  displaySmall: base.displaySmall?.copyWith(fontWeight: FontWeight.w400),
  headlineLarge: base.headlineLarge?.copyWith(fontWeight: FontWeight.w400),
  headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w400),
  headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w400),
  titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w400),
  titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w400),
  titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w400),
  bodyLarge: base.bodyLarge?.copyWith(fontWeight: FontWeight.w400),
  bodyMedium: base.bodyMedium?.copyWith(fontWeight: FontWeight.w400),
  bodySmall: base.bodySmall?.copyWith(fontWeight: FontWeight.w400),
  labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w400),
  labelMedium: base.labelMedium?.copyWith(fontWeight: FontWeight.w400),
  labelSmall: base.labelSmall?.copyWith(fontWeight: FontWeight.w400),
);

const chineseFontFallback = <String>[
  'PosterSans',
  'Microsoft YaHei',
  'PingFang SC',
  'Noto Sans CJK SC',
  'sans-serif',
];

class ImportedFont {
  const ImportedFont({required this.id, required this.name});
  final String id, name;
  String get family => 'Imported_$id';
}

/// Keeps a private copy of each imported font so moving the original file does
/// not change the poster after restarting the app.
class FontLibrary extends ChangeNotifier {
  final fonts = <ImportedFont>[];
  String selectedFamily = defaultFontFamily;
  bool _disposed = false;

  String get selectedName =>
      fonts.where((font) => font.family == selectedFamily).firstOrNull?.name ??
      '思源黑体（默认）';

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    for (final raw in prefs.getStringList('importedFonts') ?? <String>[]) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final id = data['id'] as String;
        if (!RegExp(r'^f[0-9]+$').hasMatch(id)) continue;
        final font = ImportedFont(id: id, name: data['name'] as String);
        final bytes = await storage.readFont(id);
        validateFont(bytes);
        await _load(font, bytes);
        if (_disposed) return;
        if (!fonts.any((item) => item.id == id)) fonts.add(font);
      } catch (_) {
        // A missing or unreadable saved font must not prevent app startup.
      }
    }
    if (_disposed) return;
    final saved = prefs.getString('posterFontFamily');
    if (fonts.any((font) => font.family == saved)) selectedFamily = saved!;
    notifyListeners();
  }

  Future<void> importFont(String name, Uint8List bytes) async {
    validateFont(bytes);
    final font = ImportedFont(
      id: 'f${DateTime.now().microsecondsSinceEpoch}',
      name: name.replaceFirst(
        RegExp(r'\.(ttf|otf)$', caseSensitive: false),
        '',
      ),
    );
    await _load(font, bytes);
    await storage.writeFont(font.id, bytes);
    if (_disposed) return;
    fonts.add(font);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('importedFonts', [
      for (final item in fonts) jsonEncode({'id': item.id, 'name': item.name}),
    ]);
    await select(font.family);
  }

  Future<void> select(String family) async {
    if (family != defaultFontFamily &&
        !fonts.any((font) => font.family == family)) {
      return;
    }
    selectedFamily = family;
    if (!_disposed) notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('posterFontFamily', family);
  }

  static Future<void> _load(ImportedFont font, Uint8List bytes) async {
    final loader = FontLoader(font.family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  static void validateFont(Uint8List bytes) {
    if (bytes.length < 12 || bytes.length > 50 * 1024 * 1024) {
      throw const FormatException('请选择有效的 TTF / OTF 字体（不超过 50 MB）。');
    }
    final data = ByteData.sublistView(bytes);
    final signature = data.getUint32(0);
    if (signature != 0x00010000 && signature != 0x4F54544F) {
      throw const FormatException('文件不是受支持的 TTF / OTF 字体。');
    }
    final count = data.getUint16(4);
    if (count == 0 || 12 + count * 16 > bytes.length) {
      throw const FormatException('字体文件不完整，请重新选择。');
    }
    final tags = <String>{};
    for (var index = 0; index < count; index++) {
      final offset = 12 + index * 16;
      tags.add(String.fromCharCodes(bytes.sublist(offset, offset + 4)));
      final start = data.getUint32(offset + 8),
          length = data.getUint32(offset + 12);
      if (start > bytes.length || length > bytes.length - start) {
        throw const FormatException('字体文件损坏，请重新选择。');
      }
    }
    if (!tags.containsAll({'head', 'cmap', 'name'}) ||
        !tags.any({'glyf', 'CFF ', 'CFF2'}.contains)) {
      throw const FormatException('该字体缺少必要的文字轮廓数据。');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
