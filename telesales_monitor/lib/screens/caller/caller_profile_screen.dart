import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../widgets/neo_button.dart';
import '../../providers/tele_provider.dart';

class CallerProfileScreen extends StatelessWidget {
  const CallerProfileScreen({super.key});

  void _showEditCallerNameDialog(BuildContext context, TeleProvider tele) {
    final nameCtrl = TextEditingController(text: tele.callerName);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              decoration: BoxDecoration(
                color: AppTheme.paper,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: AppTheme.ink900, width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'SET CALLER NAME',
                        style: AppTheme.label(size: 11, color: AppTheme.ink900, letterSpacing: 0.16),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppTheme.ink900),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your preferred caller display name for admin leaderboard & call sync.',
                    style: AppTheme.body(size: 12, color: AppTheme.muted),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.ink900, width: 1.2),
                    ),
                    child: TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      style: AppTheme.bodyBold(size: 14),
                      decoration: const InputDecoration(
                        hintText: 'e.g. Priyanka Panchal / Sales Agent 1',
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.person_outline, color: AppTheme.ink900),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  NeoButton.accent(
                    onTap: () {
                      final newName = nameCtrl.text.trim();
                      if (newName.isNotEmpty) {
                        tele.setCallerName(newName);
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppTheme.ink900,
                            content: Text(
                              'Caller name updated to "$newName"',
                              style: AppTheme.bodyBold(size: 12, color: AppTheme.greenNeon),
                            ),
                          ),
                        );
                      }
                    },
                    child: Center(
                      child: Text(
                        'SAVE CALLER NAME →',
                        style: AppTheme.label(size: 11, color: AppTheme.ink900, letterSpacing: 0.12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);

    final callerName = tele.callerName.isNotEmpty ? tele.callerName : 'Device Caller';
    final phoneStr = tele.verifiedTrackingNumber.isNotEmpty ? tele.verifiedTrackingNumber : '+91 98250 12340';
    final total = tele.trackedTotalCalls;
    final connected = tele.trackedConnectedCalls;
    final talkTimeStr = tele.trackedTalkTimeFormatted;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile Header Card
          NeoCard(
            backgroundColor: AppTheme.ink900,
            shadowColor: AppTheme.ink900,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'DEVICE CALLER PROFILE',
                      style: AppTheme.label(size: 9, color: AppTheme.limeYellow, letterSpacing: 0.18),
                    ),
                    GestureDetector(
                      onTap: () => _showEditCallerNameDialog(context, tele),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.greenNeon,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppTheme.ink900, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.edit, size: 11, color: AppTheme.ink900),
                            const SizedBox(width: 4),
                            Text(
                              'EDIT NAME',
                              style: AppTheme.label(size: 8, color: AppTheme.ink900),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  callerName,
                  style: AppTheme.headline(size: 26, color: AppTheme.paper),
                ),
                const SizedBox(height: 2),
                Text(
                  '$phoneStr · ${tele.activeSimLabel}',
                  style: AppTheme.body(size: 11, color: AppTheme.lightMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Auto-Record Toggle Card
          NeoCard(
            backgroundColor: AppTheme.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.paper,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.ink900, width: 1.2),
                  ),
                  child: const Icon(Icons.mic, color: AppTheme.greenDark, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AUTO-RECORD ALL CALLS',
                        style: AppTheme.label(size: 9, color: AppTheme.ink900, letterSpacing: 0.1),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Auto-records audio during active ongoing calls',
                        style: AppTheme.body(size: 11, color: AppTheme.muted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: tele.autoRecordEnabled,
                  activeThumbColor: AppTheme.greenNeon,
                  activeTrackColor: AppTheme.ink900,
                  onChanged: (_) => tele.toggleAutoRecord(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Live Metrics Card
          NeoCard(
            backgroundColor: AppTheme.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LIVE PERFORMANCE SUMMARY',
                  style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.18),
                ),
                const SizedBox(height: 16),
                _TargetBar(
                  label: 'Total calls ($total logged)',
                  progress: total > 0 ? (total / 50).clamp(0.05, 1.0) : 0.05,
                  color: AppTheme.greenNeon,
                ),
                const SizedBox(height: 14),
                _TargetBar(
                  label: 'Connected ($connected calls)',
                  progress: total > 0 ? (connected / total).clamp(0.05, 1.0) : 0.05,
                  color: AppTheme.limeYellow,
                ),
                const SizedBox(height: 14),
                _TargetBar(
                  label: 'Talk time ($talkTimeStr)',
                  progress: total > 0 ? 0.75 : 0.05,
                  color: AppTheme.greenGrass,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TargetBar extends StatelessWidget {
  final String label;
  final double progress;
  final Color color;

  const _TargetBar({
    required this.label,
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTheme.bodyBold(size: 12)),
            Text('${(progress * 100).toInt()}%', style: AppTheme.mono(size: 11, color: AppTheme.muted)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: AppTheme.paper,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppTheme.ink900, width: 0.8),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(color: color),
            ),
          ),
        ),
      ],
    );
  }
}
