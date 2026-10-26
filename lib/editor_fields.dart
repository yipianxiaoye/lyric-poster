import 'package:flutter/material.dart';

String formatPoints(double value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

/// A controlled numeric field keeps incomplete edits visible while applying
/// only valid, printable values to the document.
class PointSizeField extends StatefulWidget {
  const PointSizeField({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
    super.key,
  });
  final String label;
  final double value, max;
  final bool Function(double) onChanged;

  @override
  State<PointSizeField> createState() => _PointSizeFieldState();
}

class _PointSizeFieldState extends State<PointSizeField> {
  late final TextEditingController input;
  String? error;
  @override
  void initState() {
    super.initState();
    input = TextEditingController(text: formatPoints(widget.value));
  }

  @override
  void didUpdateWidget(PointSizeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final parsed = double.tryParse(input.text);
    if (oldWidget.value != widget.value && parsed != widget.value) {
      input.text = formatPoints(widget.value);
      error = null;
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: input,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: 'pt',
        helperText: '4–${formatPoints(widget.max)} pt，可输入小数',
        errorText: error,
      ),
      onChanged: (text) {
        final value = double.tryParse(text);
        if (value == null ||
            !value.isFinite ||
            value < 4 ||
            value > widget.max) {
          setState(() => error = '请输入 4–${formatPoints(widget.max)} 的数值');
          return;
        }
        final accepted = widget.onChanged(value);
        setState(() => error = accepted ? null : '当前纸张放不下此字号，请减小数值');
      },
    ),
  );
}

class LiveTextField extends StatefulWidget {
  const LiveTextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.maxLines = 1,
    this.hint,
    super.key,
  });
  final String label, value;
  final String? hint;
  final int maxLines;
  final bool Function(String) onChanged;
  @override
  State<LiveTextField> createState() => _LiveTextFieldState();
}

class _LiveTextFieldState extends State<LiveTextField> {
  late final TextEditingController input;
  String? error;
  @override
  void initState() {
    super.initState();
    input = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(LiveTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && input.text != widget.value) {
      input.text = widget.value;
      error = null;
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: input,
    minLines: widget.maxLines == 1 ? 1 : 5,
    maxLines: widget.maxLines,
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
      alignLabelWithHint: widget.maxLines > 1,
      errorText: error,
      errorMaxLines: 3,
    ),
    onChanged: (text) {
      final accepted = widget.onChanged(text);
      setState(() => error = accepted ? null : '当前纸张放不下这些文字，请减小字号或增大纸张。');
    },
  );
}
