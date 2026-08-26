import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../providers/tele_provider.dart';

class CallerDashboard extends StatelessWidget {
  const CallerDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);

    final total = tele.trackedTotalCalls;
    final connected = tele.trackedConnectedCalls;
    final talkTimeStr = tele.trackedTalkTimeFormatted;
    final missed = tele.trackedMissedCalls;
    final incoming = tele.trackedIncomingCalls;
    final outgoing = tele.trackedOutgoingCalls;
    final targetProgress = total > 0 ? (total / 50).clamp(0.0, 1.0) : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // My Calls Today Card
          NeoCard(
            backgroundColor: AppTheme.ink900,
            shadowColor: AppTheme.ink900,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '01 · REALTIME METRICS',
                      style: AppTheme.label(size: 9, color: AppTheme.limeYellow, letterSpacing: 0.18),
                    ),
                    Text(
                      tele.activeSimLabel,
                      style: AppTheme.mono(size: 9, color: AppTheme.lightMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$total', style: AppTheme.headline(size: 48, color: AppTheme.white)),
                    const SizedBox(width: 10),
                    Text('$talkTimeStr on calls', style: AppTheme.italicSerif(size: 17, color: AppTheme.limeYellow)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$connected connected · $outgoing outgoing · $incoming incoming',
                  style: AppTheme.body(size: 11, color: AppTheme.lightMuted),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 6,
                    color: AppTheme.ink800,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: targetProgress > 0 ? targetProgress : 0.05,
                      child: Container(
                        decoration: const BoxDecoration(gradient: AppTheme.greenGradient),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 2x1 Quick Stats
          Row(
            children: [
              Expanded(
                child: NeoCard(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('02 · CONNECTED', style: AppTheme.label(size: 9, color: AppTheme.muted)),
                      const SizedBox(height: 3),
                      Text('$connected', style: AppTheme.headline(size: 26, color: AppTheme.ink900)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NeoCard(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('03 · MISSED / REJECT', style: AppTheme.label(size: 9, color: AppTheme.muted)),
                      const SizedBox(height: 3),
                      Text('$missed', style: AppTheme.headline(size: 26, color: AppTheme.redMissed)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Outgoing vs Incoming Breakdown
          NeoCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('04 · CALL SPLIT', style: AppTheme.label(size: 9, color: AppTheme.muted, letterSpacing: 0.18)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('OUTGOING', style: AppTheme.label(size: 8, color: AppTheme.muted)),
                          const SizedBox(height: 2),
                          Text('$outgoing', style: AppTheme.headline(size: 20, color: AppTheme.orangePill)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('INCOMING', style: AppTheme.label(size: 8, color: AppTheme.muted)),
                          const SizedBox(height: 2),
                          Text('$incoming', style: AppTheme.headline(size: 20, color: AppTheme.greenDark)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('TALK TIME', style: AppTheme.label(size: 8, color: AppTheme.muted)),
                          const SizedBox(height: 2),
                          Text(talkTimeStr, style: AppTheme.headline(size: 20, color: AppTheme.ink900)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
