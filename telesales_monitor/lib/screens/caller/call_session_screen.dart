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
  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);
    final lead = tele.activeCallLead ?? widget.lead ?? (tele.sessionQueue.isNotEmpty ? tele.sessionQueue.first : LeadModel(
      id: 'demo',
      name: 'Ganesh Enterprises',
      phone: '+91 98400 11223',
      status: LeadStatus.newLead,
      attempts: 0,
      dateAdded: DateTime.now(),
      lastCallDate: DateTime.now(),
      note: '',
    ));

    final initials = lead.name.isNotEmpty
        ? lead.name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join('').toUpperCase()
        : 'GE';

    final sessionNum = (tele.sessionIndex + 1);
    final totalInSession = (tele.sessionQueue.isNotEmpty ? tele.sessionQueue.length : 5);

    return Scaffold(
      backgroundColor: AppTheme.ink900,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            children: [
              // Top Status Header: OUTBOUND · SIM 1 · SESSION 2 / 5
              Text(
                'OUTBOUND · SIM 1 · SESSION $sessionNum / $totalInSession',
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

              // Contact Name
              Text(
                lead.name.toUpperCase(),
                style: AppTheme.headline(size: 28, color: AppTheme.white),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),

              // Phone & Live Timer
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
                  Text(
                    tele.callTimerFormatted,
                    style: AppTheme.mono(size: 14, color: AppTheme.limeYellow, weight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Conference Banner Pill
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                decoration: BoxDecoration(
                  color: AppTheme.ink800,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppTheme.greenNeon, width: 1.2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.greenNeon,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'CONFERENCE · ARJUN RAO (MANAGER) JOINED',
                        style: AppTheme.label(size: 9.5, color: AppTheme.white, letterSpacing: 0.08),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 6 Circular Action Buttons (2 Rows of 3)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallActionButton(
                    icon: tele.isCallMuted ? Icons.mic_off : Icons.mic_none,
                    label: tele.isCallMuted ? 'MUTED' : 'MUTE',
                    isActive: tele.isCallMuted,
                    activeBg: AppTheme.white,
                    activeFg: AppTheme.ink900,
                    onTap: tele.toggleMute,
                  ),
                  _CallActionButton(
                    icon: Icons.dialpad,
                    label: 'KEYPAD',
                    isActive: tele.isKeypadOpen,
                    onTap: tele.toggleKeypad,
                  ),
                  _CallActionButton(
                    icon: Icons.bluetooth,
                    label: 'AUDIO',
                    isActive: true,
                    activeBg: AppTheme.greenNeon,
                    activeFg: AppTheme.ink900,
                    onTap: () {},
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallActionButton(
                    icon: Icons.person_add_alt_1,
                    label: 'CONFERENCE',
                    onTap: () {},
                  ),
                  _CallActionButton(
                    icon: Icons.pause,
                    label: 'HOLD',
                    isActive: tele.isCallOnHold,
                    onTap: tele.toggleHold,
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
              const SizedBox(height: 14),

              // Audio Output Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.ink800,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.greenNeon, width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AUDIO OUTPUT',
                      style: AppTheme.label(size: 8.5, color: AppTheme.greenNeon, letterSpacing: 0.15),
                    ),
                    const SizedBox(height: 8),
                    _AudioDeviceRow(
                      name: 'iPhone Earpiece',
                      isSelected: tele.selectedAudioOutput == 'iPhone Earpiece',
                      onSelect: () => tele.setAudioOutput('iPhone Earpiece'),
                    ),
                    const SizedBox(height: 6),
                    _AudioDeviceRow(
                      name: 'Speaker',
                      isSelected: tele.selectedAudioOutput == 'Speaker',
                      onSelect: () => tele.setAudioOutput('Speaker'),
                    ),
                    const SizedBox(height: 6),
                    _AudioDeviceRow(
                      name: 'BT Headset · boAt 331',
                      isSelected: tele.selectedAudioOutput.contains('BT Headset'),
                      onSelect: () => tele.setAudioOutput('BT Headset · boAt 331'),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Bottom Actions Row: LOG OUTCOME & END CALL
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        tele.endSessionCall();
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => LogOutcomeScreen(lead: lead),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: AppTheme.limeYellow,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppTheme.ink900, width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            '✓ LOG OUTCOME',
                            style: AppTheme.label(size: 11, color: AppTheme.ink900, letterSpacing: 0.12),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        tele.endSessionCall();
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => LogOutcomeScreen(lead: lead),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: AppTheme.redOverdue,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppTheme.ink900, width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            'END CALL',
                            style: AppTheme.label(size: 11, color: AppTheme.white, letterSpacing: 0.12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'ENDING THE CALL OPENS LOG OUTCOME AUTOMATICALLY',
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
  final Color? activeBg;
  final Color? activeFg;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.activeBg,
    this.activeFg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isActive ? (activeBg ?? AppTheme.greenNeon) : AppTheme.ink800;
    final fg = isActive ? (activeFg ?? AppTheme.ink900) : AppTheme.white;
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

class _AudioDeviceRow extends StatelessWidget {
  final String name;
  final bool isSelected;
  final VoidCallback onSelect;

  const _AudioDeviceRow({
    required this.name,
    required this.isSelected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            name,
            style: AppTheme.mono(
              size: 11.5,
              color: isSelected ? AppTheme.limeYellow : AppTheme.muted,
              weight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          if (isSelected)
            Text(
              '✓',
              style: AppTheme.mono(size: 12, color: AppTheme.limeYellow, weight: FontWeight.w700),
            ),
        ],
      ),
    );
  }
}
