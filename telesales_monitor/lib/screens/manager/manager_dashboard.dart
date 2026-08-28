import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
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

    int totalTalkSec = 0;
    for (var c in logs) {
      totalTalkSec += c.duration.inSeconds;
    }
    final avgSecs = connectedCalls > 0 ? (totalTalkSec ~/ connectedCalls) : 0;
    final avgM = avgSecs ~/ 60;
    final avgS = avgSecs % 60;
    final avgDurationStr = avgSecs > 0 ? (avgM > 0 ? '${avgM}m ${avgS}s' : '${avgS}s') : '0s';
    final connectRateStr = totalCalls > 0 ? ((connectedCalls / totalCalls) * 100).toStringAsFixed(1) : '0.0';

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
    final List<Map<String, dynamic>> hourlyData = [];
    if (stats != null && stats['hourlyCalls'] is List && (stats['hourlyCalls'] as List).isNotEmpty) {
      final rawList = stats['hourlyCalls'] as List;
      int maxCnt = 1;
      for (var h in rawList) {
        final c = (h is Map && h['calls'] is int) ? h['calls'] as int : 0;
        if (c > maxCnt) maxCnt = c;
      }
      for (var h in rawList) {
        final cnt = (h is Map && h['calls'] is int) ? h['calls'] as int : 0;
        final hour = (h is Map && h['hour'] != null) ? h['hour'].toString() : '';
        final isPk = (h is Map && h['isPeak'] == true) || (cnt > 0 && cnt == maxCnt);
        final val = cnt > 0 ? (cnt / maxCnt).clamp(0.15, 1.0) : 0.08;
        hourlyData.add({
          'hour': hour,
          'val': val,
          'calls': '$cnt',
          'isPeak': isPk,
        });
      }
    } else {
      final List<int> hourCounts = List.filled(11, 0);
      for (var c in logs) {
        final h = c.timestamp.hour;
        if (h >= 9 && h <= 19) {
          hourCounts[h - 9]++;
        }
      }
      int maxHourCount = 1;
      for (var cnt in hourCounts) {
        if (cnt > maxHourCount) maxHourCount = cnt;
      }
      final List<String> hourLabels = ['9AM', '10AM', '11AM', '12PM', '1PM', '2PM', '3PM', '4PM', '5PM', '6PM', '7PM'];
      for (int i = 0; i < 11; i++) {
        final cnt = hourCounts[i];
        final val = cnt > 0 ? (cnt / maxHourCount).clamp(0.15, 1.0) : 0.08;
        hourlyData.add({
          'hour': hourLabels[i],
          'val': val,
          'calls': '$cnt',
          'isPeak': cnt > 0 && cnt == maxHourCount,
        });
      }
    }

    String calendarHeaderLabel = '📅 TODAY';
    if (tele.selectedDateRange != null) {
      calendarHeaderLabel = '📅 ${DateFormat('d MMM').format(tele.selectedDateRange!.start)} - ${DateFormat('d MMM').format(tele.selectedDateRange!.end)}'.toUpperCase();
    } else if (tele.selectedCustomDate != null) {
      calendarHeaderLabel = '📅 ${DateFormat('d MMM yyyy').format(tele.selectedCustomDate!).toUpperCase()}';
    } else if (tele.selectedTimeFilter == 1) {
      calendarHeaderLabel = '📅 THIS WEEK';
    } else if (tele.selectedTimeFilter == 2) {
      calendarHeaderLabel = '📅 THIS MONTH';
    }

    final hasCustomCalendar = tele.selectedDateRange != null || tele.selectedCustomDate != null;
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
            TopHeader(
              title: 'DASHBOARD',
              userName: tele.currentUserName,
              selectedSimIndex: 1,
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  flex: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.ink900,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.ink800, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.groups_rounded, size: 14, color: AppTheme.limeYellow),
                        const SizedBox(width: 6),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: tele.selectedTeamFilter,
                              isExpanded: true,
                              dropdownColor: AppTheme.ink900,
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppTheme.limeYellow),
                              style: AppTheme.mono(size: 10, color: AppTheme.white),
                              onChanged: (val) {
                                if (val != null) tele.setTeamFilter(val);
                              },
                              items: tele.availableTeams.map((t) {
                                return DropdownMenuItem<String>(
                                  value: t,
                                  child: Text(t == 'ALL' ? '🏢 ALL TEAMS' : '🏢 $t', overflow: TextOverflow.ellipsis),
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
                Expanded(
                  flex: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.ink900,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.ink800, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_rounded, size: 14, color: AppTheme.limeYellow),
                        const SizedBox(width: 6),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: tele.userFilterOptions.contains(tele.selectedUserFilter) ? tele.selectedUserFilter : 'ALL',
                              isExpanded: true,
                              dropdownColor: AppTheme.ink900,
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppTheme.limeYellow),
                              style: AppTheme.mono(size: 10, color: AppTheme.white),
                              onChanged: (val) {
                                if (val != null) tele.setUserFilter(val);
                              },
                              items: tele.userFilterOptions.map((u) {
                                return DropdownMenuItem<String>(
                                  value: u,
                                  child: Text(u == 'ALL' ? '👤 ALL USERS' : '👤 $u', overflow: TextOverflow.ellipsis),
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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.greenNeon,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person_add_alt_1_rounded, size: 16, color: AppTheme.ink900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppTheme.ink900, width: 1.5),
                boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
              ),
              child: Row(
                children: [
                  _buildPeriodTab(tele, 'TODAY', 0),
                  _buildPeriodTab(tele, 'WEEK', 1),
                  _buildPeriodTab(tele, 'MONTH', 2),
                ],
              ),
            ),
            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => _showCalendarPicker(context, tele),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: hasCustomCalendar ? AppTheme.limeYellow : AppTheme.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppTheme.ink900, width: 1.5),
                      boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_month_rounded, size: 16, color: AppTheme.ink900),
                        const SizedBox(width: 6),
                        Text(
                          calendarHeaderLabel,
                          style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.12),
                        ),
                        if (hasCustomCalendar) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              tele.setCustomDate(null);
                              tele.setDateRange(null);
                            },
                            child: const Icon(Icons.cancel_rounded, size: 16, color: AppTheme.ink900),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Text(
                  tele.activeSimLabel,
                  style: AppTheme.label(size: 9.5, color: AppTheme.muted, letterSpacing: 0.1),
                ),
              ],
            ),
            const SizedBox(height: 12),

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

            // 2x1 Row: AVG DURATION & CONNECT RATE
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
                        Text('AVG DURATION', style: AppTheme.label(size: 9, color: AppTheme.muted)),
                        const SizedBox(height: 4),
                        Text(avgDurationStr, style: AppTheme.headline(size: 26, color: AppTheme.greenDark)),
                        const SizedBox(height: 2),
                        Text('per connected call', style: AppTheme.body(size: 10.5, color: AppTheme.muted)),
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
                        Text('CONNECT RATE', style: AppTheme.label(size: 9, color: AppTheme.muted)),
                        const SizedBox(height: 4),
                        Text('$connectRateStr%', style: AppTheme.headline(size: 26, color: AppTheme.ink900)),
                        const SizedBox(height: 2),
                        Text('$connectedCalls of $totalCalls picked', style: AppTheme.body(size: 10.5, color: AppTheme.muted)),
                      ],
                    ),
                  ),
                ),
              ],
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

  Widget _buildPeriodTab(TeleProvider tele, String label, int index) {
    final isSelected = tele.selectedTimeFilter == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => tele.setTimeFilter(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.ink900 : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            child: Text(
              label,
              style: AppTheme.label(
                size: 9,
                color: isSelected ? AppTheme.limeYellow : AppTheme.ink900,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showCalendarPicker(BuildContext context, TeleProvider tele) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppTheme.paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppTheme.ink900, width: 2),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.ink900,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('FILTER BY CALENDAR DATE', style: AppTheme.headline(size: 16, color: AppTheme.ink900)),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.event, color: AppTheme.ink900),
              title: Text('Select Specific Date', style: AppTheme.bodyBold(size: 14)),
              subtitle: Text('Filter team activity for a single specific day', style: AppTheme.body(size: 12, color: AppTheme.muted)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.ink900, width: 1.5),
              ),
              tileColor: AppTheme.white,
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await showDatePicker(
                  context: context,
                  initialDate: tele.selectedCustomDate ?? DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now(),
                  builder: (c, child) => Theme(
                    data: Theme.of(c).copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: AppTheme.ink900,
                        onPrimary: AppTheme.limeYellow,
                        surface: AppTheme.paper,
                        onSurface: AppTheme.ink900,
                      ),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) tele.setCustomDate(picked);
              },
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.date_range, color: AppTheme.ink900),
              title: Text('Select Date Range', style: AppTheme.bodyBold(size: 14)),
              subtitle: Text('Filter team activity across custom date range', style: AppTheme.body(size: 12, color: AppTheme.muted)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.ink900, width: 1.5),
              ),
              tileColor: AppTheme.white,
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now(),
                  initialDateRange: tele.selectedDateRange ?? DateTimeRange(
                    start: DateTime.now().subtract(const Duration(days: 7)),
                    end: DateTime.now(),
                  ),
                  builder: (c, child) => Theme(
                    data: Theme.of(c).copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: AppTheme.ink900,
                        onPrimary: AppTheme.limeYellow,
                        surface: AppTheme.paper,
                        onSurface: AppTheme.ink900,
                      ),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) tele.setDateRange(picked);
              },
            ),
          ],
        ),
      ),
    );
  }
}
