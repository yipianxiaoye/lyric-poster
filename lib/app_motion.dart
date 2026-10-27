import 'package:flutter/material.dart';

/// Animates the current content without keeping a second, outgoing subtree.
/// This keeps editor focus, global keys and live poster gestures unambiguous.
class AppMotion extends StatefulWidget {
  const AppMotion({required this.identity, required this.child, super.key});

  final Object? identity;
  final Widget child;

  @override
  State<AppMotion> createState() => _AppMotionState();
}

class _AppMotionState extends State<AppMotion>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 1,
  );
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final _opacity = Tween<double>(begin: .84, end: 1).animate(_curve);
  late final _position = Tween<Offset>(
    begin: const Offset(0, .015),
    end: Offset.zero,
  ).animate(_curve);
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant AppMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      if (_reduceMotion) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity,
    child: SlideTransition(position: _position, child: widget.child),
  );
}
