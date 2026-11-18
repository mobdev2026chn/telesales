import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/tele_provider.dart';
import '../../services/call_recording_setup.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';

/// "Call recording" (More screen entry, dashboard banner).
class CallRecordingSetupScreen extends StatelessWidget {
  const CallRecordingSetupScreen({super.key, this.autoStart = false});

  /// Start turning recording on right away (the dashboard banner's one tap).
  final bool autoStart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.paper,
      appBar: AppBar(
        backgroundColor: AppTheme.paper,
        foregroundColor: AppTheme.ink900,
        elevation: 0,
        title: Text('Call recording', style: AppTheme.headline(size: 20)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: CallRecordingSetupPanel(autoStart: autoStart),
        ),
      ),
    );
  }
}

/// One status ("Call recording is ON / OFF") and one button that does every step in a row:
/// Android's permission prompts, the battery exemption, autostart (brands that need it, once) and,
/// only where AskEVA records calls itself, the Accessibility switch. Each settings screen it opens
/// continues the flow when the caller comes back. Also embedded as a step of the onboarding flow.
class CallRecordingSetupPanel extends StatefulWidget {
  const CallRecordingSetupPanel({super.key, this.autoStart = false});

  final bool autoStart;

  @override
  State<CallRecordingSetupPanel> createState() => _CallRecordingSetupPanelState();
}

class _CallRecordingSetupPanelState extends State<CallRecordingSetupPanel> with WidgetsBindingObserver {
  static const _autostartPromptedKey = 'recording_autostart_prompted';

  RecordingSetupStatus? _status;
  bool _loading = true;

  /// The one-tap flow is running.
  bool _flowActive = false;
  /// A step is awaiting (permission prompt): lifecycle events must not start another.
  bool _stepRunning = false;
  /// A settings screen of the flow is open: continue when the app is back in front.
  bool _waitingForReturn = false;
  /// The app actually went to the background after that screen was opened (a late "resumed" from an
  /// earlier permission prompt must not count as coming back).
  bool _leftApp = false;
  bool _askedBattery = false;
  bool _askedAccessibility = false;

  /// Shown under the button when the flow stopped before recording was on.
  String? _hint;
  bool _hintOffersAppInfo = false;

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh().then((_) {
      if (widget.autoStart && mounted && _status?.recordingReady != true) _startFlow();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _leftApp = true;
      return;
    }
    if (_waitingForReturn) {
      if (!_leftApp) return;
      _waitingForReturn = false;
      _continueFlow();
    } else if (!_stepRunning) {
      _refresh();
    }
  }

  /// Marks a settings screen as opened by the flow, just before opening it.
  void _expectReturn() {
    _leftApp = false;
    _waitingForReturn = true;
  }

  Future<RecordingSetupStatus?> _refresh() async {
    if (!_isAndroid) {
      setState(() => _loading = false);
      return null;
    }
    final tele = context.read<TeleProvider>();
    final s = await CallRecordingChannel.status(tele.currentUserId);
    if (!mounted) return s;
    setState(() {
      _status = s;
      _loading = false;
      if (s?.recordingReady == true) _hint = null;
    });
    await tele.refreshRecordingSetupStatus();
    return s;
  }

  void _startFlow() {
    setState(() {
      _flowActive = true;
      _askedBattery = false;
      _askedAccessibility = false;
      _hint = null;
      _hintOffersAppInfo = false;
    });
    _continueFlow();
  }

  /// Runs the next missing step. Returns early while a settings screen is open; resumed on return.
  Future<void> _continueFlow() async {
    if (!_flowActive || _stepRunning || !mounted) return;
    _stepRunning = true;
    try {
      final tele = context.read<TeleProvider>();
      var s = await _refresh();
      if (s == null) return _finish();

      // 1. Android's permission prompts, all in one batch
      if (!s.permissionsGranted) {
        await tele.requestNativePermissions();
        s = await _refresh();
        if (s == null) return _finish();
        if (!s.permissionsGranted) {
          return _finish(
            hint: 'Allow every permission Android asks for, otherwise calls cannot be recorded. '
                'If nothing pops up, open App info → Permissions and allow Phone, Call logs, '
                'Microphone and Music and audio.',
            appInfo: true,
          );
        }
      }
      await tele.syncCallMonitor();

      // 2. Keep call tracking alive all day
      if (!s.batteryOptimizationIgnored && !_askedBattery) {
        _askedBattery = true;
        _expectReturn();
        if (await CallRecordingChannel.requestIgnoreBatteryOptimizations()) return;
        _waitingForReturn = false;
      }

      // 3. Brands that close background apps: their autostart page, once per install
      final guide = dialerGuideFor(s.manufacturer, s.brand);
      if (guide.needsAutostart) {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool(_autostartPromptedKey) != true) {
          await prefs.setBool(_autostartPromptedKey, true);
          _expectReturn();
          if (await CallRecordingChannel.openAutostartSettings()) return;
          _waitingForReturn = false;
        }
      }

      // 4. Only where AskEVA records calls itself: the Accessibility switch
      if (s.needsAccessibility && !s.accessibilityEnabled) {
        if (_askedAccessibility) {
          return _finish(
            hint: 'Turn on "AskEVA Call Recording" in Accessibility (under Installed apps). If its switch is '
                'greyed out, open App info → ⋮ → Allow restricted settings, then tap Turn on again.',
            appInfo: true,
          );
        }
        _askedAccessibility = true;
        _expectReturn();
        if (await CallRecordingChannel.openAccessibilitySettings()) return;
        _waitingForReturn = false;
        return _finish(hint: 'Open Settings → Accessibility → AskEVA Call Recording and turn it on.');
      }

      _finish();
    } finally {
      _stepRunning = false;
    }
  }

  void _finish({String? hint, bool appInfo = false}) {
    if (!mounted) return;
    setState(() {
      _flowActive = false;
      _waitingForReturn = false;
      _hint = hint;
      _hintOffersAppInfo = appInfo;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAndroid) {
      return _card(
        icon: Icons.info_outline,
        iconColor: AppTheme.ink900,
        title: 'NOT AVAILABLE',
        text: 'Call recording is available on Android phones only. iPhones do not allow apps to record '
            'or read call recordings.',
      );
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(color: AppTheme.greenDark)),
      );
    }

    final s = _status;
    final ready = s?.recordingReady == true;
    final String text;
    if (ready) {
      text = s!.builtInTrusted
          ? 'Your phone records every work call (both voices) and AskEVA uploads it automatically.'
          : s.speakerFallbackActive
              ? 'AskEVA records every work call. Calls switch to the loudspeaker so the customer is recorded too.'
              : 'AskEVA records every work call and uploads it automatically.';
    } else {
      text = 'Tap the button and allow what Android asks for. Recording then runs by itself on every work call.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          icon: ready ? Icons.check_circle : Icons.mic_off_rounded,
          iconColor: ready ? AppTheme.greenDark : AppTheme.orangePill,
          title: ready ? 'CALL RECORDING IS ON' : 'CALL RECORDING IS OFF',
          text: text,
          footer: [
            if (!ready) ...[
              const SizedBox(height: 14),
              _turnOnButton(),
            ],
            if (_hint != null && !ready) ...[
              const SizedBox(height: 10),
              Text(_hint!, style: AppTheme.body(size: 12, color: AppTheme.ink700)),
              if (_hintOffersAppInfo)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () async {
                      await CallRecordingChannel.openAppInfo();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.greenDark,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                    ),
                    child: Text('OPEN APP INFO', style: AppTheme.label(size: 10, color: AppTheme.greenDark)),
                  ),
                ),
            ],
            if ((s?.pendingUploads ?? 0) > 0) ...[
              const SizedBox(height: 10),
              Text(
                '${s!.pendingUploads} recording(s) waiting to upload — sent automatically when online.',
                style: AppTheme.mono(size: 10, color: AppTheme.muted),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _turnOnButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _flowActive ? null : _startFlow,
        icon: _flowActive
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.ink900),
              )
            : const Icon(Icons.fiber_manual_record, size: 16, color: AppTheme.redOverdue),
        label: Text(
          _flowActive ? 'TURNING ON…' : 'TURN ON RECORDING',
          style: AppTheme.label(size: 11, color: AppTheme.ink900, letterSpacing: 0.1),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: AppTheme.limeYellow,
          disabledBackgroundColor: AppTheme.limeYellow,
          side: const BorderSide(color: AppTheme.ink900, width: 1.2),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _card({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String text,
    List<Widget> footer = const [],
  }) {
    return NeoCard(
      backgroundColor: AppTheme.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 26, color: iconColor),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: AppTheme.headline(size: 17))),
            ],
          ),
          const SizedBox(height: 8),
          Text(text, style: AppTheme.body(size: 12.5, color: AppTheme.ink700)),
          ...footer,
        ],
      ),
    );
  }
}
