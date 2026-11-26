import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/tele_provider.dart';
import '../../services/call_recording_setup.dart';
import '../../theme/app_theme.dart';
import '../../widgets/askeva_phone_app_prompt.dart';
import '../../widgets/call_recording_disclosure.dart';
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
  /// The caller left "Phone by Google" from here: guide them to the new Phone app's auto-record until
  /// AskEVA finds its first recording.
  static const _dialerSwitchKey = 'recording_dialer_switch_started';

  RecordingSetupStatus? _status;
  bool _loading = true;
  bool _dialerSwitchStarted = false;

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
  /// The Accessibility switch is still off: show the exact steps (with buttons) instead of a hint.
  bool _showAccessibilitySteps = false;

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
    final prefs = await SharedPreferences.getInstance();
    var switchStarted = prefs.getBool(_dialerSwitchKey) == true;
    if (switchStarted && s != null && s.builtInTrusted) {
      await prefs.remove(_dialerSwitchKey); // the new Phone app's recordings are arriving: done
      switchStarted = false;
    }
    if (!mounted) return s;
    setState(() {
      _status = s;
      _loading = false;
      _dialerSwitchStarted = switchStarted;
      if (s?.recordingReady == true) _hint = null;
      if (s?.recordingReady == true || s?.accessibilityEnabled == true) _showAccessibilitySteps = false;
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
      _showAccessibilitySteps = false;
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
        if (_askedAccessibility) return _finish(accessibilitySteps: true);
        // Google Play's prominent disclosure: what the service does and collects, and an explicit AGREE,
        // before Android's Accessibility settings open
        if (!mounted) return;
        if (!await askCallRecordingConsent(context)) {
          return _finish(hint: 'Call recording stays off. Tap TURN ON RECORDING when you want to switch it on.');
        }
        _askedAccessibility = true;
        _expectReturn();
        if (await CallRecordingChannel.openAccessibilitySettings()) return;
        _waitingForReturn = false;
        return _finish(accessibilitySteps: true);
      }

      _finish();
    } finally {
      _stepRunning = false;
    }
  }

  /// Settings → Default apps, where the caller picks the phone's own Phone app instead of Phone by Google.
  /// The status is read again when they come back (didChangeAppLifecycleState).
  Future<void> _chooseDialer(RecordingSetupStatus s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dialerSwitchKey, true);
    if (!mounted) return;
    setState(() => _dialerSwitchStarted = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!await CallRecordingChannel.openDefaultAppsSettings()) {
      messenger?.showSnackBar(SnackBar(
        content: Text('Open Settings → Apps → Default apps → Phone app and pick "${s.builtInDialerName}".'),
      ));
    }
  }

  /// AskEVA's call screen instead of the phone's (asks first where the phone's recorder would stop).
  Future<void> _becomePhoneApp() async {
    final s = _status;
    await askToUseAskEvaAsPhoneApp(context, stopsPhoneRecorder: s?.askevaDialerStopsPhoneRecorder ?? true);
    if (mounted) await _refresh();
  }

  void _finish({String? hint, bool appInfo = false, bool accessibilitySteps = false}) {
    if (!mounted) return;
    setState(() {
      _flowActive = false;
      _waitingForReturn = false;
      _hint = hint;
      _hintOffersAppInfo = appInfo;
      _showAccessibilitySteps = accessibilitySteps;
    });
  }

  /// The "AskEVA Call Recording" switch is still off: buttons that take the agent straight there (the
  /// Accessibility page, AskEVA highlighted where the phone supports it) instead of written menu paths.
  /// Android 13+ greys the switch out for apps installed outside Google Play until "Allow restricted
  /// settings" in App info: Android offers no direct link to that menu item, so it is named on the button.
  Widget _accessibilitySteps(RecordingSetupStatus? s) {
    final restricted = (s?.sdkInt ?? 0) >= 33;
    Widget link(String label, Future<bool> Function() open) => Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () async {
              await open();
            },
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.greenDark,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
            ),
            child: Text(label, style: AppTheme.label(size: 10, color: AppTheme.greenDark)),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Turn on "AskEVA Call Recording"', style: AppTheme.bodyBold(size: 12, color: AppTheme.ink900)),
        link('OPEN ACCESSIBILITY SETTINGS', CallRecordingChannel.openAccessibilitySettings),
        if (restricted) link('SWITCH GREYED OUT? ⋮ → ALLOW RESTRICTED SETTINGS', CallRecordingChannel.openAppInfo),
      ],
    );
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
            if (_showAccessibilitySteps && !ready && s?.accessibilityEnabled != true) ...[
              const SizedBox(height: 12),
              _accessibilitySteps(s),
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
        if (s != null && s.askevaIsDialer) ...[
          const SizedBox(height: 12),
          _askevaDialerCard(),
        ] else if (s != null && s.usesGoogleDialer) ...[
          const SizedBox(height: 12),
          s.canSwitchFromGoogleDialer ? _switchDialerCard(s) : _googleOnlyCard(s),
        ] else if (s != null && _dialerSwitchStarted && !s.builtInTrusted) ...[
          const SizedBox(height: 12),
          _autoRecordCard(s),
        ] else if (s != null && s.canOfferAskEvaDialer) ...[
          const SizedBox(height: 12),
          _askevaCallScreenCard(),
        ],
      ],
    );
  }

  /// The phone's own Phone app (Samsung, vivo, ...) records calls: AskEVA's call screen is optional and
  /// stops that recorder, so it says so and asks before Android's dialog.
  Widget _askevaCallScreenCard() {
    return _card(
      icon: Icons.phone_in_talk_rounded,
      iconColor: AppTheme.ink900,
      title: 'ASKEVA CALL SCREEN',
      text: 'Calls can open in AskEVA\'s own call screen (with the lead\'s name) instead of your phone\'s. '
          'Your phone\'s call recorder then stops: AskEVA records through the microphone with the loudspeaker '
          'on, so the customer is recorded only on loudspeaker.',
      footer: [
        const SizedBox(height: 14),
        _pillButton(
          label: 'USE ASKEVA AS PHONE APP',
          icon: const Icon(Icons.phone_in_talk_rounded, size: 16, color: AppTheme.ink900),
          onPressed: _becomePhoneApp,
        ),
      ],
    );
  }

  /// "Phone by Google" is the default, but the phone also has its maker's own Phone app.
  Widget _switchDialerCard(RecordingSetupStatus s) {
    final name = s.builtInDialerName;
    return _card(
      icon: Icons.swap_horiz_rounded,
      iconColor: AppTheme.orangePill,
      title: 'SWITCH YOUR PHONE APP',
      text: 'Your calls go through "Phone by Google", which keeps its call recordings to itself. AskEVA can '
          'then only record through the microphone, so the customer may not be heard. Make your phone\'s own '
          '"$name" app the default Phone app and every call is recorded with both voices.',
      footer: [
        const SizedBox(height: 10),
        _steps([
          'Tap CHOOSE PHONE APP below.',
          'Tap "Phone app" (or "Calling app") and pick "$name".',
          'Come back here: AskEVA shows how to turn on its automatic call recording.',
        ]),
        const SizedBox(height: 14),
        _pillButton(
          label: 'CHOOSE PHONE APP',
          icon: const Icon(Icons.phone_rounded, size: 16, color: AppTheme.ink900),
          onPressed: () => _chooseDialer(s),
        ),
      ],
    );
  }

  /// "Phone by Google" is the only Phone app: nothing to switch to, the loudspeaker is the fallback.
  /// AskEVA can become the Phone app here (nothing to lose: no phone recorder to stop).
  Widget _googleOnlyCard(RecordingSetupStatus s) {
    return _card(
      icon: Icons.volume_up_rounded,
      iconColor: AppTheme.orangePill,
      title: 'KEEP CALLS ON LOUDSPEAKER',
      text: 'This phone only has "Phone by Google", which keeps its call recordings to itself. AskEVA records '
          'work calls through the microphone and switches on the loudspeaker so the customer is recorded too. '
          'Do not use earphones or Bluetooth on work calls: the customer would not be recorded.',
      footer: [
        if (s.canOfferAskEvaDialer) ...[
          const SizedBox(height: 12),
          Text(
            'AskEVA can also be this phone\'s Phone app: calls then open in AskEVA\'s own call screen, with '
            'the lead\'s name, and the loudspeaker switches on by itself. Android still gives AskEVA only the '
            'microphone, so the customer is recorded only on loudspeaker.',
            style: AppTheme.body(size: 12, color: AppTheme.ink700),
          ),
          const SizedBox(height: 12),
          _pillButton(
            label: 'USE ASKEVA AS PHONE APP',
            icon: const Icon(Icons.phone_in_talk_rounded, size: 16, color: AppTheme.ink900),
            onPressed: _becomePhoneApp,
          ),
        ],
      ],
    );
  }

  /// AskEVA is the phone's Phone app.
  Widget _askevaDialerCard() {
    return _card(
      icon: Icons.phone_in_talk_rounded,
      iconColor: AppTheme.greenDark,
      title: 'ASKEVA IS YOUR PHONE APP',
      text: 'Calls open in AskEVA\'s call screen and the loudspeaker switches on by itself, so the customer is '
          'recorded. If you switch the speaker off during a call, only your voice is recorded. To go back to '
          'your previous Phone app: tap CHANGE PHONE APP → Phone app.',
      footer: [
        const SizedBox(height: 14),
        _pillButton(
          label: 'CHANGE PHONE APP',
          icon: const Icon(Icons.swap_horiz_rounded, size: 16, color: AppTheme.ink900),
          onPressed: () async {
            await CallRecordingChannel.openDefaultAppsSettings();
          },
        ),
      ],
    );
  }

  /// Just left "Phone by Google": the new Phone app records only once its auto-record is on.
  Widget _autoRecordCard(RecordingSetupStatus s) {
    final guide = dialerGuideFor(s.manufacturer, s.brand);
    return _card(
      icon: Icons.fiber_manual_record,
      iconColor: AppTheme.redOverdue,
      title: 'TURN ON AUTO-RECORD',
      text: 'Now switch on automatic call recording in your Phone app, for all calls:',
      footer: [
        const SizedBox(height: 10),
        _steps(guide.steps),
        const SizedBox(height: 8),
        Text(
          'After your next work call this screen shows "Your phone records every work call".',
          style: AppTheme.body(size: 12, color: AppTheme.ink700),
        ),
        const SizedBox(height: 14),
        _pillButton(
          label: 'OPEN CALL RECORDING SETTINGS',
          icon: const Icon(Icons.settings_rounded, size: 16, color: AppTheme.ink900),
          onPressed: () async {
            final messenger = ScaffoldMessenger.maybeOf(context);
            if (!await CallRecordingChannel.openDialerRecordingSettings()) {
              messenger?.showSnackBar(const SnackBar(
                content: Text('Open your Phone app → ⋮ → Settings → Call recording.'),
              ));
            }
          },
        ),
      ],
    );
  }

  Widget _steps(List<String> steps) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${i + 1}. ${steps[i]}', style: AppTheme.body(size: 12, color: AppTheme.ink700)),
          ),
      ],
    );
  }

  Widget _turnOnButton() {
    return _pillButton(
      onPressed: _flowActive ? null : _startFlow,
      icon: _flowActive
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.ink900),
            )
          : const Icon(Icons.fiber_manual_record, size: 16, color: AppTheme.redOverdue),
      label: _flowActive ? 'TURNING ON…' : 'TURN ON RECORDING',
    );
  }

  Widget _pillButton({required String label, required Widget icon, VoidCallback? onPressed}) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: Text(
          label,
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
