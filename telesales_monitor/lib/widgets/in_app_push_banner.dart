import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart';
import 'notifications_sheet.dart';

/// Floating push notification banner matching the top overlay banner design in the user screenshot.
/// Features:
/// - Smooth slide-down & fade-in animation at the top of the screen
/// - Circular app avatar on the left
/// - Title with timestamp indicator: "Title • now 🔔"
/// - 2-line message text
/// - Right dropdown / dismiss arrow
/// - Swipe-up to dismiss, tap to view all notifications, auto-hide after 5 seconds
class InAppPushBanner {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void showGlobal({
    required String title,
    required String message,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 6),
  }) {
    final overlayState = appNavigatorKey.currentState?.overlay;
    if (overlayState == null) return;

    _dismissTimer?.cancel();
    _currentEntry?.remove();
    _currentEntry = null;

    OverlayEntry? entry;
    entry = OverlayEntry(
      builder: (context) => _InAppPushBannerWidget(
        title: title,
        message: message,
        onTap: () {
          _dismissTimer?.cancel();
          if (_currentEntry != null) {
            _currentEntry?.remove();
            _currentEntry = null;
          }
          if (onTap != null) {
            onTap();
          } else {
            final navContext = appNavigatorKey.currentContext;
            if (navContext != null) {
              NotificationsSheet.show(navContext);
            }
          }
        },
        onDismiss: () {
          _dismissTimer?.cancel();
          if (_currentEntry != null) {
            _currentEntry?.remove();
            _currentEntry = null;
          }
        },
      ),
    );

    _currentEntry = entry;
    overlayState.insert(entry);

    _dismissTimer = Timer(duration, () {
      if (_currentEntry == entry) {
        _currentEntry?.remove();
        _currentEntry = null;
      }
    });
  }
}

class _InAppPushBannerWidget extends StatefulWidget {
  final String title;
  final String message;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _InAppPushBannerWidget({
    required this.title,
    required this.message,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_InAppPushBannerWidget> createState() => _InAppPushBannerWidgetState();
}

class _InAppPushBannerWidgetState extends State<_InAppPushBannerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
      reverseDuration: const Duration(milliseconds: 260),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));

    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    await _animController.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 6,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _slideAnim,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: widget.onTap,
              onVerticalDragUpdate: (details) {
                if (details.primaryDelta != null && details.primaryDelta! < -4) {
                  _dismiss();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 22,
                      spreadRadius: 1,
                      offset: Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Color(0x0A000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                  border: Border.all(
                    color: const Color(0x0F000000),
                    width: 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Left App Avatar Icon
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF0D5C75),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x400D5C75),
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/images/ask_eva_logo.png',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.notifications_active_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Middle content: Title with emoji + time + message
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  widget.title,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1E293B),
                                    letterSpacing: -0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Text(
                                ' • now ',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w400,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              const Text('🔔', style: TextStyle(fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.message,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF475569),
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Right down-arrow / dismiss button
                    GestureDetector(
                      onTap: _dismiss,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF1F5F9),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Color(0xFF64748B),
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
