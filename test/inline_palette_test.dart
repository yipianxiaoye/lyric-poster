import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_poster/color_picker.dart';

void main() {
  testWidgets('内嵌调色盘即时更新，HEX 校验且保留编辑光标', (tester) async {
    var color = Colors.white;
    late StateSetter refresh;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              refresh = setState;
              return SizedBox(
                width: 300,
                child: SingleChildScrollView(
                  child: ColorPaletteEditor(
                    value: color,
                    onChanged: (value) => setState(() => color = value),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    final field = find.byKey(const ValueKey('inline-color-hex'));
    await tester.enterText(field, 'D6F1E7');
    await tester.pump();
    expect(color, const Color(0xFFD6F1E7));
    final editing = tester.widget<TextField>(field).controller!;
    editing.selection = const TextSelection.collapsed(offset: 2);
    refresh(() {});
    await tester.pump();
    expect(editing.selection.baseOffset, 2);

    await tester.enterText(field, 'invalid');
    await tester.pump();
    expect(color, const Color(0xFFD6F1E7));
    expect(find.text('请输入 6 位十六进制颜色'), findsOneWidget);

    refresh(() => color = const Color(0xFFEDE2FA));
    await tester.pump();
    expect(editing.text, 'EDE2FA');
    expect(find.text('请输入 6 位十六进制颜色'), findsNothing);

    refresh(() => color = const Color(0xFFD6F1E7));
    await tester.pump();
    expect(editing.text, 'D6F1E7');

    final saturation = find.byKey(const ValueKey('inline-color-sv'));
    await tester.ensureVisible(saturation);
    await tester.pumpAndSettle();
    await tester.tap(saturation);
    await tester.pump();
    expect(color, isNot(const Color(0xFFD6F1E7)));
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('内嵌调色盘可选择预设并适应窄侧栏', (tester) async {
    Color color = Colors.white;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 220,
              child: SingleChildScrollView(
                child: ColorPaletteEditor(
                  value: color,
                  onChanged: (value) => setState(() => color = value),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final mint = find.byTooltip('薄荷 · #D6F1E7');
    await tester.ensureVisible(mint);
    await tester.pumpAndSettle();
    await tester.tap(mint);
    await tester.pump();
    expect(color, const Color(0xFFD6F1E7));
    expect(tester.takeException(), isNull);
  });
}
