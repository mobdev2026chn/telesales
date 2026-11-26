import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/tele_provider.dart';
import '../services/dialer_service.dart';
import '../theme/app_theme.dart';

/// Makes AskEVA the phone's Phone app, so calls show AskEVA's call screen instead of the phone's.
/// Where the current Phone app records calls (Samsung, vivo, ...) it first says that recorder stops,
/// and asks. Android then shows its own confirmation. True when AskEVA is the Phone app afterwards.
Future<bool> askToUseAskEvaAsPhoneApp(BuildContext context, {required bool stopsPhoneRecorder}) async {
  if (stopsPhoneRecorder) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.paper,
        title: Text('USE ASKEVA AS PHONE APP?', style: AppTheme.headline(size: 20, color: AppTheme.ink900)),
        content: Text(
          'Calls will open in AskEVA\'s call screen, not your phone\'s.\n\n'
          'Your phone\'s own call recorder stops. AskEVA records through the microphone and switches the '
          'loudspeaker on: if you switch it off, only your voice is recorded.\n\n'
          'You can switch back any time: More → Call recording → CHANGE PHONE APP.',
          style: AppTheme.body(size: 13, color: AppTheme.ink900),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('CANCEL', style: AppTheme.label(size: 11, color: AppTheme.ink900)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('USE ASKEVA', style: AppTheme.label(size: 11, color: AppTheme.greenDark)),
          ),
        ],
      ),
    );
    if (ok != true) return false;
  }
  final isPhoneApp = await DialerService.instance.requestDefaultDialerRole();
  if (!context.mounted) return isPhoneApp;
  await context.read<TeleProvider>().refreshRecordingSetupStatus();
  if (!isPhoneApp && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
      content: Text('AskEVA was not set as the Phone app. Tap again and choose AskEVA in the dialog.'),
    ));
  }
  return isPhoneApp;
}

/// Slim strip where calls are made (Dialer tab, calling session) while the phone's own call screen
/// still shows: one tap to use AskEVA's call screen instead. Hidden once AskEVA is the Phone app.
class UseAskEvaCallScreenStrip extends StatelessWidget {
  const UseAskEvaCallScreenStrip({super.key, this.dark = false});

  /// On the dark calling-session screen.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<TeleProvider>().recordingSetupStatus;
    if (s == null || !s.canOfferAskEvaDialer) return const SizedBox.shrink();
    final fg = dark ? AppTheme.limeYellow : AppTheme.ink900;
    return GestureDetector(
      onTap: () => askToUseAskEvaAsPhoneApp(context, stopsPhoneRecorder: s.askevaDialerStopsPhoneRecorder),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: dark ? Colors.transparent : AppTheme.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: fg, width: 1.2),
        ),
        child: Row(
          children: [
            Icon(Icons.phone_in_talk_rounded, size: 16, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Calls open in your phone\'s call screen',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(size: 12, color: fg),
              ),
            ),
            const SizedBox(width: 8),
            Text('SHOW IN ASKEVA →', style: AppTheme.label(size: 9.5, color: fg)),
          ],
        ),
      ),
    );
  }
}
