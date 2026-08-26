import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class NeoButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final Color backgroundColor;
  final Color borderColor;
  final Color shadowColor;
  final double shadowOffset;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Gradient? gradient;

  const NeoButton({
    super.key,
    required this.child,
    required this.onTap,
    this.backgroundColor = AppTheme.ink900,
    this.borderColor = AppTheme.ink900,
    this.shadowColor = AppTheme.greenNeon,
    this.shadowOffset = 4.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    this.borderRadius = 16.0,
    this.gradient,
  });

  const NeoButton.pill({
    super.key,
    required this.child,
    required this.onTap,
    this.backgroundColor = AppTheme.white,
    this.borderColor = AppTheme.ink900,
    this.shadowColor = AppTheme.ink900,
    this.shadowOffset = 3.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    this.borderRadius = 999.0,
    this.gradient,
  });

  const NeoButton.accent({
    super.key,
    required this.child,
    required this.onTap,
    this.backgroundColor = AppTheme.greenNeon,
    this.borderColor = AppTheme.ink900,
    this.shadowColor = AppTheme.ink900,
    this.shadowOffset = 4.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    this.borderRadius = 16.0,
    this.gradient = AppTheme.greenGradient,
  });

  @override
  State<NeoButton> createState() => _NeoButtonState();
}

class _NeoButtonState extends State<NeoButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final currentOffset = _isPressed ? 0.0 : widget.shadowOffset;
    final currentTranslation = _isPressed ? widget.shadowOffset : 0.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: Transform.translate(
        offset: Offset(currentTranslation, currentTranslation),
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.gradient == null ? widget.backgroundColor : null,
            gradient: widget.gradient,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: AppTheme.neoBorder(color: widget.borderColor),
            boxShadow: currentOffset > 0
                ? AppTheme.neoShadow(color: widget.shadowColor, offset: currentOffset)
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
