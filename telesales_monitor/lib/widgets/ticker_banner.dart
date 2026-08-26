import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class TickerBanner extends StatefulWidget {
  final String text;
  const TickerBanner({
    super.key,
    this.text = 'DIAL · TRACK · CONVERT — EVERY CALL COUNTS · DIAL · TRACK · CONVERT — EVERY CALL COUNTS · ',
  });

  @override
  State<TickerBanner> createState() => _TickerBannerState();
}

class _TickerBannerState extends State<TickerBanner> with SingleTickerProviderStateMixin {
  late final ScrollController _scrollController;
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();

    _animController.addListener(() {
      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        if (maxScroll > 0) {
          _scrollController.jumpTo(_animController.value * maxScroll);
        }
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
        gradient: AppTheme.greenGradient,
        border: Border(
          top: BorderSide(color: AppTheme.ink900, width: 1),
          bottom: BorderSide(color: AppTheme.ink900, width: 1),
        ),
      ),
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(
          children: [
            Text(
              widget.text + widget.text,
              style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.18),
            ),
          ],
        ),
      ),
    );
  }
}
