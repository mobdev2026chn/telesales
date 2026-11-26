import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/tele_provider.dart';
import '../screens/call/in_call_screen.dart';
import '../services/dialer_service.dart';
import '../theme/app_theme.dart';

/// App-wide (MaterialApp.builder), for AskEVA as the phone's Phone app:
///  - opens the call screen when a call starts (signed in or not: calls must always be answerable),
///  - shows a "return to call" bar while the call screen is hidden,
///  - turns tel: links / dial pad requests from other apps into the Dialer tab with the number typed in.
/// Without AskEVA as the Phone app no events arrive and this only shows [child].
class CallOverlay extends StatefulWidget {
  const CallOverlay({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends State<CallOverlay> with WidgetsBindingObserver {
  final ValueNotifier<CallEvent?> _call = ValueNotifier<CallEvent?>(null);
  StreamSubscription<CallEvent>? _callSub;
  StreamSubscription<void>? _dialSub;
  Route<void>? _route;

  /// Call the screen was opened for: a new call id opens it again (e.g. call waiting).
  String _openedFor = '';

  /// Dial request that arrived before anyone was signed in.
  String? _pendingDial;
  TeleProvider? _tele;

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    if (!_supported) return;
    WidgetsBinding.instance.addObserver(this);
    _listenIfPhoneApp();
    _dialSub = DialerService.instance.dialRequests.listen((_) => _takeDial());
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeDial());
  }

  /// Call events exist only while AskEVA is the Phone app: listen from then on (checked again on
  /// every return to the app, e.g. after the "Use AskEVA as Phone app" dialog).
  Future<void> _listenIfPhoneApp() async {
    if (_callSub != null) return;
    final status = await DialerService.instance.getDialerStatus();
    if (!mounted || _callSub != null || !status.isDefault) return;
    _callSub = DialerService.instance.callEvents.listen(
      _onCall,
      onError: (_) {},
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _listenIfPhoneApp();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tele = Provider.of<TeleProvider>(context, listen: false);
    if (!identical(tele, _tele)) {
      _tele?.removeListener(_tryPendingDial);
      _tele = tele..addListener(_tryPendingDial);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callSub?.cancel();
    _dialSub?.cancel();
    _tele?.removeListener(_tryPendingDial);
    _call.dispose();
    super.dispose();
  }

  Future<void> _takeDial() async {
    final number = await DialerService.instance.takePendingDial();
    if (number == null || !mounted) return;
    _pendingDial = number;
    _tryPendingDial();
  }

  void _tryPendingDial() {
    final n = _pendingDial;
    if (n != null && (_tele?.openDialerWith(n) ?? false)) _pendingDial = null;
  }

  void _onCall(CallEvent e) {
    if (!e.isLive) {
      _call.value = null;
      _openedFor = '';
      _closeScreen();
      if (mounted) setState(() {});
      return;
    }
    _call.value = e;
    if (e.callId != _openedFor) {
      _openedFor = e.callId;
      _openScreen();
    }
    if (mounted) setState(() {});
  }

  void _openScreen() {
    if (_route != null || !mounted) return;
    final nav = widget.navigatorKey.currentState;
    if (nav == null) {
      // Cold start from a call: the navigator is not built yet
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_call.value?.isLive ?? false) _openScreen();
      });
      return;
    }
    final route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => InCallScreen(call: _call, onMinimize: _closeScreen),
    );
    _route = route;
    nav.push(route).then((_) {
      if (identical(_route, route)) _route = null;
      if (mounted) setState(() {});
    });
    setState(() {});
  }

  /// Hides the call screen (the call goes on: the bar brings it back).
  void _closeScreen() {
    final route = _route;
    if (route == null) return;
    _route = null;
    final nav = widget.navigatorKey.currentState;
    if (nav != null) {
      if (route.isCurrent) {
        nav.pop();
      } else if (route.isActive) {
        nav.removeRoute(route);
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final e = _call.value;
    final showBar = e != null && e.isLive && _route == null;
    if (!showBar) return widget.child;
    return Column(
      children: [
        _ReturnToCallBar(call: e, onTap: _openScreen),
        // The bar already covers the status bar
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

class _ReturnToCallBar extends StatefulWidget {
  const _ReturnToCallBar({required this.call, required this.onTap});

  final CallEvent call;
  final VoidCallback onTap;

  @override
  State<_ReturnToCallBar> createState() => _ReturnToCallBarState();
}

class _ReturnToCallBarState extends State<_ReturnToCallBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.call;
    final tele = Provider.of<TeleProvider>(context, listen: false);
    final name =
        tele.callerNameFor(e.phoneNumber) ??
        (e.displayName.isNotEmpty ? e.displayName : e.phoneNumber);
    return Material(
      color: e.isRingingIn ? AppTheme.orangePill : AppTheme.greenNeon,
      child: InkWell(
        onTap: widget.onTap,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.call_rounded,
                  size: 18,
                  color: AppTheme.ink900,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${callStatusText(e, DateTime.now())} · $name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyBold(size: 13, color: AppTheme.ink900),
                  ),
                ),
                Text(
                  'RETURN TO CALL',
                  style: AppTheme.label(size: 9.5, color: AppTheme.ink900),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
