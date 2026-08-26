import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../widgets/neo_button.dart';
import '../../providers/tele_provider.dart';

class ManagerDashboard extends StatelessWidget {
  final VoidCallback onNavigateToBoard;
  const ManagerDashboard({super.key, required this.onNavigateToBoard});

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);
    final stats = tele.backendStats;

    final totalCalls = stats != null
        ? (stats['totalCalls'] as int? ?? tele.trackedTotalCalls)
        : tele.trackedTotalCalls;
    final connectedCalls = stats != null
        ? (stats['connectedCalls'] as int? ?? tele.trackedConnectedCalls)
        : tele.trackedConnectedCalls;
    final talkTimeFormatted = stats != null
        ? (stats['talkTimeFormatted'] as String? ?? tele.trackedTalkTimeFormatted)
        : tele.trackedTalkTimeFormatted;
    final uniqueClients = stats != null
        ? (stats['uniqueClients'] as int? ?? tele.simTrackedCallLogs.map((c) => c.phoneNumber).toSet().length)
        : tele.simTrackedCallLogs.map((c) => c.phoneNumber).toSet().length;
    final teamCount = stats != null
        ? (stats['teamCount'] as int? ?? tele.employees.length)
        : tele.employees.length;
    final incoming = stats != null
        ? (stats['incoming'] as int? ?? tele.trackedIncomingCalls)
        : tele.trackedIncomingCalls;
    final outgoing = stats != null
        ? (stats['outgoing'] as int? ?? tele.trackedOutgoingCalls)
        : tele.trackedOutgoingCalls;
    final missed = stats != null
        ? (stats['missed'] as int? ?? tele.trackedMissedCalls)
        : tele.trackedMissedCalls;
    final neverAttended = stats != null
        ? (stats['neverAttended'] as int? ?? tele.trackedNeverAttendedCalls)
        : tele.trackedNeverAttendedCalls;

    final topTalkTimeName = stats != null && stats['topPerformer'] is Map
        ? stats['topPerformer']['name'] ?? tele.callerName.toUpperCase()
        : (stats != null && stats['topTalkTime'] is Map
            ? stats['topTalkTime']['name'] ?? tele.callerName.toUpperCase()
            : tele.callerName.toUpperCase());

    final topTalkTimeDuration = stats != null && stats['topPerformer'] is Map
        ? stats['topPerformer']['duration'] ?? tele.trackedTalkTimeFormatted.toUpperCase()
        : (stats != null && stats['topTalkTime'] is Map
            ? stats['topTalkTime']['duration'] ?? tele.trackedTalkTimeFormatted.toUpperCase()
            : tele.trackedTalkTimeFormatted.toUpperCase());

    final currentDateStr = DateFormat('d MMM yyyy').format(DateTime.now()).toUpperCase();

    final List<Map<String, dynamic>> hourlyData = (stats != null && stats['hourlyCalls'] is List)
        ? (stats['hourlyCalls'] as List).map((h) {
            final c = h['calls'] as int? ?? 0;
            final isPeak = h['isPeak'] as bool? ?? false;
            final val = totalCalls > 0 ? (c / (totalCalls > 0 ? totalCalls : 1)).clamp(0.1, 1.0) : 0.1;
            return {
              'hour': h['hour']?.toString() ?? '',
              'val': val,
              'isPeak': isPeak,
            };
          }).toList()
        : [
            {'hour': '9A', 'val': 0.15, 'isPeak': false},
            {'hour': '10A', 'val': 0.35, 'isPeak': false},
            {'hour': '11A', 'val': 0.55, 'isPeak': false},
            {'hour': '12P', 'val': 0.45, 'isPeak': false},
            {'hour': '1P', 'val': 0.70, 'isPeak': false},
            {'hour': '2P', 'val': 0.90, 'isPeak': true},
            {'hour': '3P', 'val': 0.60, 'isPeak': false},
            {'hour': '4P', 'val': 0.45, 'isPeak': false},
            {'hour': '5P', 'val': 0.35, 'isPeak': false},
            {'hour': '6P', 'val': 0.20, 'isPeak': false},
          ];

    return RefreshIndicator(
      color: AppTheme.greenNeon,
      backgroundColor: AppTheme.ink900,
      onRefresh: () async {
        await tele.fetchBackendData();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'DASHBOARD',
                          style: AppTheme.headline(size: 30, color: AppTheme.ink900),
                        ),
                        Text(
                          '.',
                          style: AppTheme.headline(size: 30, color: AppTheme.greenNeon),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ASKEVA · TEAM VIEW · $currentDateStr',
                      style: AppTheme.mono(size: 10, color: AppTheme.muted),
                    ),
                  ],
                ),
                NeoButton.pill(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  onTap: () => tele.logout(),
                  child: Row(
                    children: [
                      Text(
                        'MANAGER',
                        style: AppTheme.label(size: 9, color: AppTheme.ink900, letterSpacing: 0.12),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.close, size: 12, color: AppTheme.ink900),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Card 01: Total Calls Today
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
                        '01 · TOTAL CALLS TODAY',
                        style: AppTheme.label(size: 9, color: AppTheme.limeYellow, letterSpacing: 0.18),
                      ),
                      Text(
                        'TEAM OF $teamCount',
                        style: AppTheme.label(size: 9, color: AppTheme.muted, letterSpacing: 0.14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$totalCalls',
                        style: AppTheme.headline(size: 48, color: AppTheme.white),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'connected $connectedCalls',
                        style: AppTheme.italicSerif(size: 17, color: AppTheme.limeYellow),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$talkTimeFormatted talk time · $uniqueClients unique clients',
                    style: AppTheme.body(size: 11, color: AppTheme.lightMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 2x2 Telemetry Grid
            Row(
              children: [
                Expanded(
                  child: NeoCard(
                    backgroundColor: AppTheme.white,
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('02 · INCOMING', style: AppTheme.label(size: 9, color: AppTheme.muted)),
                        const SizedBox(height: 4),
                        Text('$incoming', style: AppTheme.headline(size: 32, color: AppTheme.greenDark)),
                        const SizedBox(height: 2),
                        Text('$incoming calls', style: AppTheme.body(size: 11, color: AppTheme.ink700)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: NeoCard(
                    backgroundColor: AppTheme.white,
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('03 · OUTGOING', style: AppTheme.label(size: 9, color: AppTheme.muted)),
                        const SizedBox(height: 4),
                        Text('$outgoing', style: AppTheme.headline(size: 32, color: AppTheme.ink900)),
                        const SizedBox(height: 2),
                        Text('$outgoing calls', style: AppTheme.body(size: 11, color: AppTheme.ink700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: NeoCard(
                    backgroundColor: AppTheme.greenNeon,
                    shadowColor: AppTheme.ink900,
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('04 · MISSED', style: AppTheme.label(size: 9, color: AppTheme.ink900)),
                        const SizedBox(height: 4),
                        Text('$missed', style: AppTheme.headline(size: 32, color: AppTheme.ink900)),
                        const SizedBox(height: 2),
                        Text('needs callback', style: AppTheme.bodyBold(size: 11, color: AppTheme.ink900)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: NeoCard(
                    backgroundColor: AppTheme.white,
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('05 · NEVER ATTENDED', style: AppTheme.label(size: 9, color: AppTheme.muted)),
                        const SizedBox(height: 4),
                        Text('$neverAttended', style: AppTheme.headline(size: 32, color: AppTheme.ink900)),
                        const SizedBox(height: 2),
                        Text('by client', style: AppTheme.body(size: 11, color: AppTheme.ink700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Hourly Calls Bar Chart
            NeoCard(
              backgroundColor: AppTheme.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'HOURLY CALLS',
                        style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.18),
                      ),
                      Text(
                        'peak 1–2 PM',
                        style: AppTheme.mono(size: 9, color: AppTheme.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 90,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: hourlyData.map((item) {
                        final val = item['val'] as double;
                        final isPeak = item['isPeak'] as bool;
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              width: 22,
                              height: (val * 65).clamp(12.0, 65.0),
                              decoration: BoxDecoration(
                                color: isPeak ? AppTheme.greenNeon : AppTheme.ink900,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item['hour'] as String,
                              style: AppTheme.mono(size: 8, color: AppTheme.muted),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Top Talk Time Banner
            GestureDetector(
              onTap: onNavigateToBoard,
              child: NeoCard(
                gradient: AppTheme.greenGradient,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TOP TALK TIME · $topTalkTimeName — $topTalkTimeDuration',
                      style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.14),
                    ),
                    const Icon(Icons.arrow_forward, size: 16, color: AppTheme.ink900),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
