import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/tele_provider.dart';
import '../../models/lead_model.dart';
import 'log_outcome_screen.dart';

class CallSessionScreen extends StatefulWidget {
  final LeadModel? lead;

  const CallSessionScreen({super.key, this.lead});

  static Future<void> push(BuildContext context, {LeadModel? lead}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallSessionScreen(lead: lead),
      ),
    );
  }

  @override
  State<CallSessionScreen> createState() => _CallSessionScreenState();
}

class _CallSessionScreenState extends State<CallSessionScreen> {
  TeleProvider? _tele;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tele ??= Provider.of<TeleProvider>(context, listen: false);
  }

  @override
  void dispose() {
    // The on-screen call timer must never keep running once this screen is gone.
    _tele?.endSessionCall(notify: false);
    super.dispose();
  }

  void _openOutcome(TeleProvider tele, LeadModel lead) {
    tele.endSessionCall();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => LogOutcomeScreen(lead: lead)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);
    final lead = tele.activeCallLead ?? widget.lead;

    if (lead == null) {
      return Scaffold(
        backgroundColor: AppTheme.ink900,
        appBar: AppBar(backgroundColor: AppTheme.ink900, foregroundColor: AppTheme.white, elevation: 0),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No lead to call. Leads assigned to you will appear in your queue.',
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 14, color: AppTheme.lightMuted),
            ),
          ),
        ),
      );
    }

    final initials = lead.name.trim().isNotEmpty
        ? lead.name.trim().split(RegExp(r'\s+')).map((w) => w.isNotEmpty ? w[0] : '').take(2).join('').toUpperCase()
        : '—';

    final sessionNum = tele.sessionIndex + 1;
    final totalInSession = tele.sessionQueue.length;
    final header = totalInSession > 0
        ? 'OUTBOUND · ${tele.workSimShortLabel} · LEAD $sessionNum / $totalInSession'
        : 'OUTBOUND · ${tele.workSimShortLabel}';

    return Scaffold(
      backgroundColor: AppTheme.ink900,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            children: [
              Text(
                header,
                style: AppTheme.mono(size: 11, color: AppTheme.greenNeon, weight: FontWeight.w700),
              ),
              const SizedBox(height: 18),

              // Large Circular Avatar with Initials
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.greenNeon,
                  border: Border.all(color: AppTheme.limeYellow, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.greenNeon.withValues(alpha: 0.35),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: AppTheme.headline(size: 38, color: AppTheme.ink900),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                lead.name.isNotEmpty ? lead.name.toUpperCase() : lead.phone,
                style: AppTheme.headline(size: 28, color: AppTheme.white),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),

              // Phone & time since dialing
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    lead.phone,
                    style: AppTheme.mono(size: 13, color: AppTheme.lightMuted),
                  ),
                  const SizedBox(width: 8),
                  Text('·', style: AppTheme.mono(size: 13, color: AppTheme.greenNeon)),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Time since the call was dialed',
                    child: Text(
                      tele.callTimerFormatted,
                      style: AppTheme.mono(size: 14, color: AppTheme.limeYellow, weight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Actions that really work from here
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallActionButton(
                    icon: Icons.call,
                    label: tele.isSessionTimerRunning ? 'REDIAL' : 'CALL',
                    isActive: !tele.isSessionTimerRunning,
                    onTap: tele.dialActiveLead,
                  ),
                  _CallActionButton(
                    icon: Icons.article_outlined,
                    label: 'SCRIPT',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: AppTheme.ink800,
                          content: Text(
                            'Script: "Hi ${lead.name}, this is ${tele.callerName} from ASKEVA regarding your telesales solutions inquiry..."',
                            style: AppTheme.body(size: 12, color: AppTheme.limeYellow),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Mute, hold, speaker and keypad are on your phone\'s call screen.',
                textAlign: TextAlign.center,
                style: AppTheme.body(size: 11, color: AppTheme.lightMuted),
              ),
              const SizedBox(height: 18),

              // WhatsApp Details Button
              GestureDetector(
                onTap: () {
                  tele.launchWhatsApp(
                    lead.phone,
                    text: 'Hello ${lead.name}, connecting with you on call regarding ASKEVA.',
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.limeYellow,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppTheme.ink900, width: 1.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.chat_bubble_outline, color: AppTheme.ink900, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'SEND DETAILS ON WHATSAPP',
                        style: AppTheme.label(size: 11, color: AppTheme.ink900, letterSpacing: 0.12),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Bottom Actions: LOG OUTCOME
              GestureDetector(
                onTap: () => _openOutcome(tele, lead),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.limeYellow,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppTheme.ink900, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      '✓ CALL FINISHED · LOG OUTCOME',
                      style: AppTheme.label(size: 11, color: AppTheme.ink900, letterSpacing: 0.12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'END THE CALL ON YOUR PHONE, THEN LOG THE OUTCOME HERE',
                style: AppTheme.label(size: 8, color: AppTheme.lightMuted, letterSpacing: 0.08),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isActive ? AppTheme.greenNeon : AppTheme.ink800;
    final fg = isActive ? AppTheme.ink900 : AppTheme.white;
    final border = isActive ? Border.all(color: AppTheme.ink900, width: 1.5) : Border.all(color: AppTheme.greenNeon.withValues(alpha: 0.5), width: 1.2);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bg,
              border: border,
            ),
            child: Icon(icon, color: fg, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: AppTheme.label(size: 8.5, color: isActive ? AppTheme.limeYellow : AppTheme.lightMuted, letterSpacing: 0.1),
          ),
        ],
      ),
    );
  }
}

