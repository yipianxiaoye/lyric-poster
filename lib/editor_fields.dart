import 'package:flutter/material.dart';

String formatPoints(double value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

class PointSizeField extends PrintValueField {
  const PointSizeField({
    required super.label,
    required super.value,
    required double max,
    required super.onChanged,
    super.key,
  }) : super(unit: 'pt', min: 4, max: max, fitError: '当前纸张放不下此字号，请减小数值');
}

/// Keep incomplete input visible while applying only valid values to the page.
class PrintValueField extends StatefulWidget {
  const PrintValueField({
    required this.label,
    required this.value,
    required this.unit,
    required this.min,
    required this.fitError,
    required this.onChanged,
    this.max,
    super.key,
  });
  final String label, unit, fitError;
  final double value, min;
  final double? max;
  final bool Function(double) onChanged;

  @override
  State<PrintValueField> createState() => _PrintValueFieldState();
}

class _PrintValueFieldState extends State<PrintValueField> {
  late final TextEditingController input;
  String? error;
  @override
  void initState() {
    super.initState();
    input = TextEditingController(text: formatPoints(widget.value));
  }

  @override
  void didUpdateWidget(PrintValueField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final parsed = double.tryParse(input.text);
    if (oldWidget.value != widget.value &&
        (parsed == null ||
            !parsed.isFinite ||
            (parsed - widget.value).abs() > 1e-9)) {
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
  Widget build(BuildContext context) {
    final max = widget.max;
    final range = max == null
        ? null
        : '${formatPoints(widget.min)}–${formatPoints(max)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: input,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: widget.label,
          suffixText: widget.unit,
          helperText: range == null ? null : '$range ${widget.unit}，可输入小数',
          errorText: error,
          errorMaxLines: 2,
        ),
        onChanged: (text) {
          final value = double.tryParse(text);
          if (value == null ||
              !value.isFinite ||
              value < widget.min ||
              (max != null && value > max)) {
            setState(
              () => error = range == null ? '请输入有效数值' : '请输入 $range 的数值',
            );
            return;
          }
          final accepted = widget.onChanged(value);
          setState(() => error = accepted ? null : widget.fitError);
        },
      ),
    );
  }
}

class LiveTextField extends StatefulWidget {
  const LiveTextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.maxLines = 1,
    this.hint,
    this.validationMessage,
    super.key,
  });
  final String label, value;
  final String? hint;
  final String? validationMessage;
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
      setState(
        () => error = accepted
            ? null
            : widget.validationMessage ?? '当前纸张放不下这些文字，请减小字号或增大纸张。',
      );
    },
  );
}
