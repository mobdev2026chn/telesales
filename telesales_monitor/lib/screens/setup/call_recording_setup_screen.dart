import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../providers/tele_provider.dart';
import '../../services/call_recording_setup.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';

/// "Call recording setup" (More screen entry).
class CallRecordingSetupScreen extends StatelessWidget {
  const CallRecordingSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.paper,
      appBar: AppBar(
        backgroundColor: AppTheme.paper,
        foregroundColor: AppTheme.ink900,
        elevation: 0,
        title: Text('Call recording setup', style: AppTheme.headline(size: 20)),
      ),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: CallRecordingSetupPanel(),
        ),
      ),
    );
  }
}

/// Status + brand-specific guidance. Also embedded as a step of the onboarding flow.
class CallRecordingSetupPanel extends StatefulWidget {
  const CallRecordingSetupPanel({super.key});

  @override
  State<CallRecordingSetupPanel> createState() => _CallRecordingSetupPanelState();
}

class _CallRecordingSetupPanelState extends State<CallRecordingSetupPanel> with WidgetsBindingObserver {
  RecordingSetupStatus? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from a settings screen: re-read what the user changed
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      setState(() => _loading = false);
      return;
    }
    final tele = context.read<TeleProvider>();
    final s = await CallRecordingChannel.status(tele.currentUserId);
    if (!mounted) return;
    setState(() {
      _status = s;
      _loading = false;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    await action();
    await _refresh();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return _infoCard(
        Icons.info_outline,
        'Call recording is available on Android phones only. iPhones do not allow apps to record or read call recordings.',
      );
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(color: AppTheme.greenDark)),
      );
    }
    final s = _status;
    final tele = context.watch<TeleProvider>();
    final guide = dialerGuideFor(s?.manufacturer ?? '', s?.brand ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'AskEVA uploads your phone\'s own call recordings (both sides of the call). '
          'If your phone has no built-in recorder, AskEVA records the call through the microphone instead.',
          style: AppTheme.body(size: 12.5, color: AppTheme.ink700),
        ),
        const SizedBox(height: 14),

        // ---- Status
        NeoCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('STATUS', style: AppTheme.label(size: 9, color: AppTheme.ink900)),
              const SizedBox(height: 8),
              _statusRow(
                'Call tracking running',
                s?.serviceRunning == true,
                subtitle: tele.isLoggedIn ? null : 'Starts after you sign in as a caller',
                action: tele.isLoggedIn && s?.serviceRunning != true
                    ? _ActionLink('Start', () => _run(() => tele.syncCallMonitor()))
                    : null,
              ),
              _statusRow(
                'Microphone allowed',
                s?.micPermission == true,
                action: s?.micPermission == true
                    ? null
                    : _ActionLink('Allow', () => _run(() async {
                          await tele.requestNativePermissions();
                          await tele.syncCallMonitor();
                        })),
              ),
              _statusRow(
                'Access to call recordings (audio files)',
                s?.mediaPermission == true,
                subtitle: 'Lets AskEVA find the recording your phone made of each work call',
                action: s?.mediaPermission == true
                    ? null
                    : _ActionLink('Allow', () => _run(() async {
                          final ok = await CallRecordingChannel.requestMediaPermission();
                          if (!ok) _snack('Allow "Music and audio" / "Files" access in the app\'s permission settings.');
                        })),
              ),
              _statusRow(
                'Battery optimisation off',
                s?.batteryOptimizationIgnored == true,
                subtitle: 'Keeps tracking alive all day',
                action: s?.batteryOptimizationIgnored == true
                    ? null
                    : _ActionLink('Fix', () => _run(() => CallRecordingChannel.requestIgnoreBatteryOptimizations())),
              ),
              _statusRow(
                'Call recording permission (Accessibility)',
                s?.accessibilityEnabled == true,
                subtitle: s?.accessibilityEnabled == true
                    ? 'Android lets AskEVA hear the call'
                    : 'Without it Android mutes the microphone during calls, and recordings are silent',
                action: s?.accessibilityEnabled == true
                    ? null
                    : _ActionLink('Turn on', () => _run(() async {
                          final ok = await CallRecordingChannel.openAccessibilitySettings();
                          if (!ok) _snack('Open Settings → Accessibility → AskEVA Call Recording and turn it on.');
                        })),
              ),
              if ((s?.lastCaptureStatus ?? '').isNotEmpty)
                _statusRow(
                  'Last call recorded with sound',
                  s?.lastCaptureStatus == 'ok',
                  pendingLabel: 'SILENT',
                  subtitle: s?.lastCaptureStatus == 'ok'
                      ? 'Audio was captured on the last work call'
                      : 'Android muted the microphone on the last work call, so nothing was uploaded. '
                          'Turn on the Accessibility permission above.',
                ),
              _statusRow(
                'Built-in recorder detected on this phone',
                s?.nativeRecorderDetected == true,
                pendingLabel: 'NOT YET',
                subtitle: s?.nativeRecorderDetected == true
                    ? 'Your phone\'s recordings are uploaded'
                    : 'Turns green after a work call once AskEVA finds your phone\'s recording',
              ),
              if ((s?.pendingUploads ?? 0) > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '${s!.pendingUploads} recording(s) waiting to upload — retried automatically when online.',
                  style: AppTheme.mono(size: 10, color: AppTheme.muted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ---- Google Phone app on a phone that has its own dialer: its recordings cannot be read
        if (s != null && s.usesGoogleDialerOnOemPhone && !s.nativeRecorderDetected) ...[
          NeoCard(
            backgroundColor: AppTheme.limeYellow,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('USE YOUR PHONE\'S OWN PHONE APP', style: AppTheme.label(size: 9, color: AppTheme.ink900)),
                const SizedBox(height: 6),
                Text(
                  'Your default Phone app is "Phone by Google". It keeps call recordings inside its own app, '
                  'where AskEVA cannot read them. Make ${guide.brandLabel}\'s own Phone app the default, then turn on '
                  'automatic call recording in it (steps below). Its recordings contain both sides of the call.',
                  style: AppTheme.body(size: 12.5),
                ),
                const SizedBox(height: 6),
                Text(
                  'Settings → Apps → Default apps → Phone app → choose "Phone" (not "Phone by Google").',
                  style: AppTheme.bodyBold(size: 12),
                ),
                const SizedBox(height: 10),
                _button('OPEN DEFAULT APPS', Icons.phone_forwarded_outlined, () async {
                  final ok = await CallRecordingChannel.openDefaultAppsSettings();
                  if (!ok) _snack('Open Settings → Apps → Default apps → Phone app.');
                }),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // ---- Brand guide
        NeoCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TURN ON AUTOMATIC CALL RECORDING', style: AppTheme.label(size: 9, color: AppTheme.ink900)),
              const SizedBox(height: 4),
              Text(
                '${guide.brandLabel}${(s?.model ?? '').isNotEmpty ? ' · ${s!.model}' : ''}',
                style: AppTheme.bodyBold(size: 14),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < guide.steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 20, child: Text('${i + 1}.', style: AppTheme.bodyBold(size: 12.5))),
                      Expanded(child: Text(guide.steps[i], style: AppTheme.body(size: 12.5))),
                    ],
                  ),
                ),
              if (guide.note != null) ...[
                const SizedBox(height: 4),
                Text(guide.note!, style: AppTheme.body(size: 11.5, color: AppTheme.muted)),
              ],
              const SizedBox(height: 12),
              _button('OPEN PHONE APP SETTINGS', Icons.settings_phone, () async {
                final ok = await CallRecordingChannel.openDialerRecordingSettings();
                if (!ok) _snack('Could not open the dialer settings. Open your Phone app manually.');
              }),
            ],
          ),
        ),

        if (guide.needsAutostart) ...[
          const SizedBox(height: 14),
          NeoCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ALLOW AUTOSTART', style: AppTheme.label(size: 9, color: AppTheme.ink900)),
                const SizedBox(height: 6),
                Text(
                  '${guide.brandLabel} phones close background apps. Allow AskEVA to "Autostart" / run in the '
                  'background so calls are tracked even when you swipe the app away.',
                  style: AppTheme.body(size: 12.5),
                ),
                const SizedBox(height: 10),
                _button('OPEN AUTOSTART SETTINGS', Icons.rocket_launch_outlined, () async {
                  await CallRecordingChannel.openAutostartSettings();
                }),
              ],
            ),
          ),
        ],

        if (s != null && !s.accessibilityEnabled) ...[
          const SizedBox(height: 14),
          NeoCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TURN ON CALL RECORDING PERMISSION', style: AppTheme.label(size: 9, color: AppTheme.ink900)),
                const SizedBox(height: 8),
                for (final step in const [
                  'Tap the button below (or open Settings → Accessibility).',
                  'Tap "Downloaded apps" / "Installed services" → "AskEVA Call Recording".',
                  'Turn it on and confirm.',
                  'If the switch is greyed out ("Restricted setting"): open App info → ⋮ → '
                      '"Allow restricted settings", then try again.',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $step', style: AppTheme.body(size: 12.5)),
                  ),
                const SizedBox(height: 6),
                _button('OPEN ACCESSIBILITY SETTINGS', Icons.accessibility_new, () async {
                  final ok = await CallRecordingChannel.openAccessibilitySettings();
                  if (!ok) _snack('Open Settings → Accessibility manually.');
                }),
                const SizedBox(height: 8),
                _button('OPEN APP INFO (RESTRICTED SETTINGS)', Icons.info_outline, () async {
                  await CallRecordingChannel.openAppInfo();
                }),
              ],
            ),
          ),
        ],

        const SizedBox(height: 14),
        _infoCard(
          Icons.record_voice_over_outlined,
          'Android mutes other apps\' microphone during calls unless the Accessibility permission above is on. '
          'Even with it, some phones capture the customer only faintly: use speakerphone for the clearest recording.',
        ),
      ],
    );
  }

  Widget _statusRow(String title, bool ok, {String? subtitle, _ActionLink? action, String pendingLabel = 'OFF'}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 20,
            color: ok ? AppTheme.greenDark : AppTheme.orangePill,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.bodyBold(size: 13)),
                if (subtitle != null) Text(subtitle, style: AppTheme.body(size: 11, color: AppTheme.muted)),
              ],
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: action.onTap,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.greenDark,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 32),
              ),
              child: Text(action.label.toUpperCase(), style: AppTheme.label(size: 10, color: AppTheme.greenDark)),
            )
          else if (!ok)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(pendingLabel, style: AppTheme.label(size: 9, color: AppTheme.orangePill)),
            ),
        ],
      ),
    );
  }

  Widget _button(String label, IconData icon, Future<void> Function() onTap) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _run(onTap),
        icon: Icon(icon, size: 16, color: AppTheme.ink900),
        label: Text(label, style: AppTheme.label(size: 10.5, color: AppTheme.ink900, letterSpacing: 0.1)),
        style: OutlinedButton.styleFrom(
          backgroundColor: AppTheme.limeYellow,
          side: const BorderSide(color: AppTheme.ink900, width: 1.2),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _infoCard(IconData icon, String text) {
    return NeoCard(
      backgroundColor: AppTheme.white,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppTheme.ink900),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppTheme.body(size: 12.5, color: AppTheme.ink700))),
        ],
      ),
    );
  }
}

class _ActionLink {
  final String label;
  final VoidCallback onTap;
  _ActionLink(this.label, this.onTap);
}
