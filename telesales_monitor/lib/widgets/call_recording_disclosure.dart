import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

/// Prefs key: the caller agreed to the call recording disclosure (asked once per install).
const String kCallRecordingDisclosureKey = 'call_recording_disclosure_accepted';

/// Google Play's prominent disclosure for the "AskEVA Call Recording" accessibility service: shown in
/// the app before Android's Accessibility settings open, and the caller must tap AGREE first. True when
/// they agreed now or earlier; false (recording stays off) for NO THANKS or Back.
Future<bool> askCallRecordingConsent(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(kCallRecordingDisclosureKey) == true) return true;
  if (!context.mounted) return false;
  final agreed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const CallRecordingDisclosureDialog(),
  );
  if (agreed == true) await prefs.setBool(kCallRecordingDisclosureKey, true);
  return agreed == true;
}

class CallRecordingDisclosureDialog extends StatelessWidget {
  const CallRecordingDisclosureDialog({super.key});

  @override
  Widget build(BuildContext context) {
    Widget section(String label, String text) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTheme.label(size: 10, color: AppTheme.greenDark)),
              const SizedBox(height: 3),
              Text(text, style: AppTheme.body(size: 13, color: AppTheme.ink900)),
            ],
          ),
        );

    return AlertDialog(
      backgroundColor: AppTheme.paper,
      title: Text('ASKEVA CALL RECORDING', style: AppTheme.headline(size: 20, color: AppTheme.ink900)),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'To record your work calls, AskEVA uses Android\'s Accessibility service. Please read how it is '
              'used before you switch it on.',
              style: AppTheme.bodyBold(size: 13, color: AppTheme.ink900),
            ),
            section(
              'WHAT IT DOES',
              'While it is on, Android lets AskEVA record your work calls through the microphone. If your '
                  'phone\'s Phone app does not record calls, it also taps the Speaker button on the call screen '
                  'once when a work call connects, so the customer is recorded too.',
            ),
            section(
              'WHAT IT LOOKS AT',
              'Only the call screen, and only to find the Speaker button. It does not read your messages or '
                  'other apps, and it never types anything.',
            ),
            section(
              'DATA COLLECTED',
              'Audio recordings of calls on your work SIM, with each call\'s number, time and length. Calls on '
                  'your personal SIM are not uploaded.',
            ),
            section(
              'HOW IT IS USED',
              'Recordings are uploaded to your company\'s AskEVA account, where your team leaders and admins can '
                  'play and rate them for quality review. They are not sold or used for advertising.',
            ),
            section(
              'YOUR CHOICE',
              'Tap AGREE to open Accessibility settings and switch on "AskEVA Call Recording". You can switch it '
                  'off any time in Settings → Accessibility; your calls are then not recorded.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('NO THANKS', style: AppTheme.label(size: 11, color: AppTheme.ink900)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('AGREE', style: AppTheme.label(size: 11, color: AppTheme.greenDark)),
        ),
      ],
    );
  }
}
