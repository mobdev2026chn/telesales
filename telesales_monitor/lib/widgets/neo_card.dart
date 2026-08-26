import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class NeoCard extends StatelessWidget {
  final Widget child;
  final Color backgroundColor;
  final Color borderColor;
  final Color shadowColor;
  final double shadowOffset;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final VoidCallback? onTap;
  final Gradient? gradient;

  const NeoCard({
    super.key,
    required this.child,
    this.backgroundColor = AppTheme.white,
    this.borderColor = AppTheme.ink900,
    this.shadowColor = AppTheme.ink900,
    this.shadowOffset = 4.0,
    this.padding = const EdgeInsets.all(14),
    this.borderRadius = 16.0,
    this.onTap,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final cardContent = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? backgroundColor : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(borderRadius),
        border: AppTheme.neoBorder(color: borderColor),
        boxShadow: shadowOffset > 0
            ? AppTheme.neoShadow(color: shadowColor, offset: shadowOffset)
            : null,
      ),
      child: child,
    );

    if (onTap == null) return cardContent;

    return GestureDetector(
      onTap: onTap,
      child: cardContent,
    );
  }
}
