import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../widgets/top_header.dart';
import '../../widgets/create_user_dialog.dart';
import '../../providers/tele_provider.dart';

class ManagerDashboard extends StatelessWidget {
  final VoidCallback onNavigateToBoard;
  const ManagerDashboard({super.key, required this.onNavigateToBoard});

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);
    final stats = tele.backendStats;

    final logs = tele.simTrackedCallLogs;
    final totalCalls = stats != null ? (stats['totalCalls'] as int? ?? tele.trackedTotalCalls) : tele.trackedTotalCalls;
    final connectedCalls = stats != null ? (stats['connectedCalls'] as int? ?? tele.trackedConnectedCalls) : tele.trackedConnectedCalls;
    final talkTimeFormatted = stats != null ? (stats['talkTimeFormatted'] as String? ?? tele.trackedTalkTimeFormatted) : tele.trackedTalkTimeFormatted;
    final uniqueClients = stats != null ? (stats['uniqueClients'] as int? ?? logs.map((c) => c.phoneNumber).where((p) => p.isNotEmpty).toSet().length) : logs.map((c) => c.phoneNumber).where((p) => p.isNotEmpty).toSet().length;
    final incoming = stats != null ? (stats['incoming'] as int? ?? tele.trackedIncomingCalls) : tele.trackedIncomingCalls;
    final outgoing = stats != null ? (stats['outgoing'] as int? ?? tele.trackedOutgoingCalls) : tele.trackedOutgoingCalls;
    final missed = stats != null ? (stats['missed'] as int? ?? tele.trackedMissedCalls) : tele.trackedMissedCalls;
    final neverAttended = stats != null ? (stats['neverAttended'] as int? ?? tele.trackedNeverAttendedCalls) : tele.trackedNeverAttendedCalls;

    String topTalkTimeName = 'NO CALLS LOGGED YET';
    String topTalkTimeDuration = '0H 00M';

    if (stats != null && stats['topPerformer'] != null) {
      final top = stats['topPerformer'] as Map<String, dynamic>;
      topTalkTimeName = top['name']?.toString() ?? 'NO CALLS LOGGED YET';
      topTalkTimeDuration = top['duration']?.toString() ?? '0H 00M';
    } else if (tele.trackedTotalCalls > 0) {
      topTalkTimeName = tele.currentUserName.toUpperCase();
      topTalkTimeDuration = tele.trackedTalkTimeFormatted.toUpperCase();
    }

    // Dynamic Hourly Bar Pattern (9AM - 6PM)
    final List<int> hourCounts = List.filled(10, 0);
    for (var c in logs) {
      final h = c.timestamp.hour;
      if (h >= 9 && h <= 18) {
        hourCounts[h - 9]++;
      }
    }
    int maxHourCount = 1;
    for (var cnt in hourCounts) {
      if (cnt > maxHourCount) maxHourCount = cnt;
    }

    final List<String> hourLabels = ['9AM', '10AM', '11AM', '12PM', '1PM', '2PM', '3PM', '4PM', '5PM', '6PM'];
    final List<Map<String, dynamic>> hourlyData = List.generate(10, (i) {
      final cnt = hourCounts[i];
      final val = cnt > 0 ? (cnt / maxHourCount).clamp(0.15, 1.0) : 0.08;
      return {
        'hour': hourLabels[i],
        'val': val,
        'calls': '$cnt',
        'isPeak': cnt > 0 && cnt == maxHourCount,
      };
    });

    final targetProgress = totalCalls > 0 ? (totalCalls / 300).clamp(0.01, 1.0) : 0.0;

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
            TopHeader(
              title: 'DASHBOARD',
              userName: tele.currentUserName,
              selectedSimIndex: 1,
            ),
            const SizedBox(height: 14),

            // Action Row: Team Selector & + ADD USER Button
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.ink900,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.ink800, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.groups_outlined, color: AppTheme.limeYellow, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              dropdownColor: AppTheme.ink900,
                              isExpanded: true,
                              value: tele.availableTeams.contains(tele.selectedTeamFilter) ? tele.selectedTeamFilter : tele.availableTeams.first,
                              icon: const Icon(Icons.arrow_drop_down, color: AppTheme.limeYellow, size: 18),
                              style: AppTheme.headline(size: 10.5, color: AppTheme.greenNeon),
                              onChanged: (val) {
                                if (val != null) {
                                  tele.setTeamFilter(val);
                                }
                              },
                              items: tele.availableTeams.map((t) {
                                return DropdownMenuItem<String>(
                                  value: t,
                                  child: Text(t == 'ALL' ? '🏢 ALL TEAMS' : '🏢 ${t.toUpperCase()}', overflow: TextOverflow.ellipsis),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => CreateUserDialog.show(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.greenNeon,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.ink900, width: 1.5),
                      boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_add_alt_1_rounded, size: 16, color: AppTheme.ink900),
                        const SizedBox(width: 4),
                        Text(
                          '+ CREATE USER',
                          style: AppTheme.label(size: 9.5, color: AppTheme.ink900, letterSpacing: 0.1),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Card 01: REALTIME TEAM CALL METRICS
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
                        '01 · REALTIME TEAM CALL METRICS',
                        style: AppTheme.label(size: 9, color: AppTheme.limeYellow, letterSpacing: 0.18),
                      ),
                      Text(
                        tele.activeSimLabel,
                        style: AppTheme.label(size: 9, color: AppTheme.muted, letterSpacing: 0.14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$totalCalls',
                        style: AppTheme.headline(size: 56, color: AppTheme.white),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$talkTimeFormatted talk',
                        style: AppTheme.italicSerif(size: 20, color: AppTheme.greenGrass),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$connectedCalls connected · $uniqueClients unique clients · target 300',
                    style: AppTheme.body(size: 11, color: AppTheme.lightMuted),
                  ),
                  const SizedBox(height: 12),

                  // Green Progress Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      height: 8,
                      color: AppTheme.ink800,
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: targetProgress,
                        child: Container(
                          decoration: const BoxDecoration(color: AppTheme.greenNeon),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 2x2 Quick Metrics Grid
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: NeoCard(
                        backgroundColor: AppTheme.white,
                        shadowColor: AppTheme.ink900,
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('02 · OUTGOING', style: AppTheme.label(size: 9, color: AppTheme.muted)),
                            const SizedBox(height: 4),
                            Text('$outgoing', style: AppTheme.headline(size: 28, color: AppTheme.orangePill)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: NeoCard(
                        backgroundColor: AppTheme.white,
                        shadowColor: AppTheme.ink900,
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('03 · INCOMING', style: AppTheme.label(size: 9, color: AppTheme.muted)),
                            const SizedBox(height: 4),
                            Text('$incoming', style: AppTheme.headline(size: 28, color: AppTheme.greenDark)),
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
                            Text('04 · MISSED', style: AppTheme.label(size: 9, color: AppTheme.white)),
                            const SizedBox(height: 4),
                            Text('$missed', style: AppTheme.headline(size: 28, color: AppTheme.white)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: NeoCard(
                        backgroundColor: AppTheme.white,
                        shadowColor: AppTheme.ink900,
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('05 · NEVER ATTENDED', style: AppTheme.label(size: 9, color: AppTheme.muted)),
                            const SizedBox(height: 4),
                            Text('$neverAttended', style: AppTheme.headline(size: 28, color: AppTheme.redMissed)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Hourly Distribution Bar Chart Card
            NeoCard(
              backgroundColor: AppTheme.white,
              shadowColor: AppTheme.ink900,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'HOURLY CALL DISTRIBUTION',
                        style: AppTheme.label(size: 9, color: AppTheme.ink900, letterSpacing: 0.18),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppTheme.ink900, width: 1),
                        ),
                        child: Text(
                          'TODAY',
                          style: AppTheme.label(size: 8, color: AppTheme.ink900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  SizedBox(
                    height: 100,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: hourlyData.map((item) {
                        final val = item['val'] as double;
                        final isPeak = item['isPeak'] as bool;
                        final calls = item['calls'] as String;

                        return Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (isPeak) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.ink900,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '$calls calls',
                                  style: AppTheme.mono(size: 7.5, color: AppTheme.limeYellow),
                                ),
                              ),
                              const SizedBox(height: 4),
                            ],
                            Container(
                              width: 22,
                              height: (val * 60).clamp(6.0, 60.0),
                              decoration: BoxDecoration(
                                color: isPeak ? AppTheme.greenNeon : AppTheme.ink900,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item['hour'] as String,
                              style: AppTheme.mono(size: 7.5, color: AppTheme.muted),
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

            // Top Talk Time Action Banner (Green Bar)
            NeoCard(
              backgroundColor: AppTheme.greenNeon,
              shadowColor: AppTheme.ink900,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              onTap: onNavigateToBoard,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Text('🏆 ', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TOP TALK TIME: $topTalkTimeName ($topTalkTimeDuration)',
                                style: AppTheme.label(size: 10, color: AppTheme.white, letterSpacing: 0.12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Tap to view team leaderboard & rankings',
                                style: AppTheme.body(size: 11, color: AppTheme.white.withValues(alpha: 0.85)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 18, color: AppTheme.white),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
