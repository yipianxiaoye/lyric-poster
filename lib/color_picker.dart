import 'package:flutter/material.dart';

const commonColors = <(String, Color)>[
  ('纯白', Color(0xFFFFFFFF)),
  ('象牙白', Color(0xFFFFFBF0)),
  ('米色', Color(0xFFF3E9D2)),
  ('浅灰', Color(0xFFF0F1F3)),
  ('暖灰', Color(0xFFDDD7CF)),
  ('纯黑', Color(0xFF151515)),
  ('石墨灰', Color(0xFF374151)),
  ('深蓝', Color(0xFF172B4D)),
  ('浅粉', Color(0xFFFCE4EC)),
  ('蜜桃', Color(0xFFFFDCC7)),
  ('鹅黄', Color(0xFFFFF3C4)),
  ('浅绿', Color(0xFFE1EBD6)),
  ('薄荷', Color(0xFFD6F1E7)),
  ('浅蓝', Color(0xFFDCEEFF)),
  ('浅紫', Color(0xFFEDE2FA)),
  ('珊瑚红', Color(0xFFE77C73)),
  ('海蓝', Color(0xFF337FA3)),
  ('森林绿', Color(0xFF276158)),
  ('梅紫', Color(0xFF75527C)),
  ('咖啡', Color(0xFF694B3D)),
];

String colorHex(Color color) => color
    .toARGB32()
    .toRadixString(16)
    .padLeft(8, '0')
    .substring(2)
    .toUpperCase();

class ColorPresets extends StatelessWidget {
  const ColorPresets({required this.value, required this.onChanged, super.key});
  final Color value;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final (name, color) in commonColors)
        Tooltip(
          message: '$name · #${colorHex(color)}',
          child: Semantics(
            label: name,
            button: true,
            selected: color == value,
            child: InkWell(
              onTap: () => onChanged(color),
              borderRadius: BorderRadius.circular(9),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: color == value
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.withValues(alpha: .55),
                    width: color == value ? 3 : 1,
                  ),
                ),
                child: color == value
                    ? Icon(
                        Icons.check,
                        size: 18,
                        color: color.computeLuminance() > .45
                            ? Colors.black87
                            : Colors.white,
                      )
                    : null,
              ),
            ),
          ),
        ),
    ],
  );
}

/// A live color editor for a docked design panel. The parent owns the selected
/// color; incomplete HEX input remains local until it is valid.
class ColorPaletteEditor extends StatefulWidget {
  const ColorPaletteEditor({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final Color value;
  final ValueChanged<Color> onChanged;

  @override
  State<ColorPaletteEditor> createState() => _ColorPaletteEditorState();
}

class _ColorPaletteEditorState extends State<ColorPaletteEditor> {
  late HSVColor hsv;
  late final TextEditingController hex;
  Color? lastEmitted;
  String? error;

  @override
  void initState() {
    super.initState();
    hsv = HSVColor.fromColor(widget.value);
    hex = TextEditingController(text: colorHex(widget.value));
  }

  @override
  void didUpdateWidget(ColorPaletteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != lastEmitted) {
      hsv = HSVColor.fromColor(widget.value);
      hex.text = colorHex(widget.value);
      error = null;
    }
    // An emitted value only identifies its immediate parent echo. A later
    // external selection of the same color must still replace incomplete input.
    lastEmitted = null;
  }

  @override
  void dispose() {
    hex.dispose();
    super.dispose();
  }

  void select(HSVColor value) {
    final color = value.toColor();
    setState(() {
      hsv = value;
      lastEmitted = color;
      hex.text = colorHex(color);
      error = null;
    });
    widget.onChanged(color);
  }

  void editHex(String text) {
    final raw = text.trim().replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(raw)) {
      setState(() => error = '请输入 6 位十六进制颜色');
      return;
    }
    final color = Color(0xFF000000 | int.parse(raw, radix: 16));
    setState(() {
      hsv = HSVColor.fromColor(color);
      lastEmitted = color;
      error = null;
    });
    widget.onChanged(color);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      LayoutBuilder(
        builder: (_, constraints) => GestureDetector(
          key: const ValueKey('inline-color-sv'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) =>
              selectSV(details.localPosition, constraints.maxWidth),
          onPanUpdate: (details) =>
              selectSV(details.localPosition, constraints.maxWidth),
          child: CustomPaint(
            painter: _SaturationPainter(hsv),
            size: Size(constraints.maxWidth, 140),
          ),
        ),
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (_, constraints) => GestureDetector(
          key: const ValueKey('inline-color-hue'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) =>
              selectHue(details.localPosition.dx, constraints.maxWidth),
          onPanUpdate: (details) =>
              selectHue(details.localPosition.dx, constraints.maxWidth),
          child: Container(
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: LinearGradient(
                colors: [
                  for (var hue = 0; hue <= 360; hue += 60)
                    HSVColor.fromAHSV(1, hue.toDouble(), 1, 1).toColor(),
                ],
              ),
            ),
            child: Align(
              alignment: Alignment(hsv.hue / 180 - 1, 0),
              child: Container(
                width: 9,
                height: 24,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: hsv.toColor(),
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const ValueKey('inline-color-hex'),
              controller: hex,
              maxLength: 7,
              decoration: InputDecoration(
                labelText: 'HEX 颜色',
                prefixText: '#',
                counterText: '',
                errorText: error,
              ),
              onChanged: editHex,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      const Text('常用颜色', style: TextStyle(fontWeight: FontWeight.w400)),
      const SizedBox(height: 10),
      ColorPresets(
        value: hsv.toColor(),
        onChanged: (color) => select(HSVColor.fromColor(color)),
      ),
    ],
  );

  void selectSV(Offset point, double width) {
    if (width <= 0) return;
    select(
      hsv
          .withSaturation((point.dx / width).clamp(0, 1))
          .withValue((1 - point.dy / 140).clamp(0, 1)),
    );
  }

  void selectHue(double x, double width) {
    if (width <= 0) return;
    select(hsv.withHue((x / width * 360).clamp(0, 359.99)));
  }
}

Future<Color?> showColorPalette(BuildContext context, Color initial) =>
    showDialog<Color>(context: context, builder: (_) => _ColorDialog(initial));

class _ColorDialog extends StatefulWidget {
  const _ColorDialog(this.initial);
  final Color initial;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late HSVColor hsv;
  late final TextEditingController hex;
  String? error;

  @override
  void initState() {
    super.initState();
    hsv = HSVColor.fromColor(widget.initial);
    hex = TextEditingController(text: colorHex(widget.initial));
  }

  @override
  void dispose() {
    hex.dispose();
    super.dispose();
  }

  void update(HSVColor value) => setState(() {
    hsv = value;
    hex.text = colorHex(value.toColor());
    error = null;
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('调色盘'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (_, constraints) => GestureDetector(
                key: const ValueKey('color-sv'),
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) =>
                    selectSV(details.localPosition, constraints.maxWidth),
                onPanUpdate: (details) =>
                    selectSV(details.localPosition, constraints.maxWidth),
                child: CustomPaint(
                  painter: _SaturationPainter(hsv),
                  size: Size(constraints.maxWidth, 180),
                ),
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (_, constraints) => GestureDetector(
                key: const ValueKey('color-hue'),
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) =>
                    selectHue(details.localPosition.dx, constraints.maxWidth),
                onPanUpdate: (details) =>
                    selectHue(details.localPosition.dx, constraints.maxWidth),
                child: Container(
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: LinearGradient(
                      colors: [
                        for (var h = 0; h <= 360; h += 60)
                          HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
                      ],
                    ),
                  ),
                  child: Align(
                    alignment: Alignment(hsv.hue / 180 - 1, 0),
                    child: Container(
                      width: 9,
                      height: 28,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: hsv.toColor(),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const ValueKey('color-hex'),
                    controller: hex,
                    maxLength: 7,
                    decoration: InputDecoration(
                      labelText: 'HEX 颜色',
                      prefixText: '#',
                      counterText: '',
                      errorText: error,
                    ),
                    onChanged: (text) {
                      final raw = text.trim().replaceFirst('#', '');
                      final parsed = int.tryParse(raw, radix: 16);
                      setState(() {
                        error = null;
                        if (raw.length == 6 && parsed != null) {
                          hsv = HSVColor.fromColor(Color(0xFF000000 | parsed));
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text('常用颜色', style: TextStyle(fontWeight: FontWeight.w400)),
            const SizedBox(height: 10),
            ColorPresets(
              value: hsv.toColor(),
              onChanged: (color) => update(HSVColor.fromColor(color)),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          final raw = hex.text.trim().replaceFirst('#', '');
          final parsed = int.tryParse(raw, radix: 16);
          if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(raw) || parsed == null) {
            setState(() => error = '请输入 6 位十六进制颜色');
            return;
          }
          Navigator.pop(context, Color(0xFF000000 | parsed));
        },
        child: const Text('应用'),
      ),
    ],
  );

  void selectSV(Offset point, double width) => update(
    hsv
        .withSaturation((point.dx / width).clamp(0, 1))
        .withValue((1 - point.dy / 180).clamp(0, 1)),
  );

  void selectHue(double x, double width) =>
      update(hsv.withHue((x / width * 360).clamp(0, 359.99)));
}

class _SaturationPainter extends CustomPainter {
  _SaturationPainter(this.color);
  final HSVColor color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white,
            HSVColor.fromAHSV(1, color.hue, 1, 1).toColor(),
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    final point = Offset(
      color.saturation * size.width,
      (1 - color.value) * size.height,
    );
    canvas.drawCircle(
      point,
      7,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      point,
      6,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SaturationPainter oldDelegate) =>
      oldDelegate.color != color;
}
