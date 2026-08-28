import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../widgets/top_header.dart';
import '../../providers/tele_provider.dart';
import '../../models/call_log_model.dart';

class CallerDashboard extends StatefulWidget {
  const CallerDashboard({super.key});

  @override
  State<CallerDashboard> createState() => _CallerDashboardState();
}

class _CallerDashboardState extends State<CallerDashboard> {
  DateTime? _selectedDate;

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);

    // Filter logs by selected date if set
    final allLogs = tele.simTrackedCallLogs;
    final logs = _selectedDate == null
        ? allLogs
        : allLogs.where((c) {
            return c.timestamp.year == _selectedDate!.year &&
                c.timestamp.month == _selectedDate!.month &&
                c.timestamp.day == _selectedDate!.day;
          }).toList();

    final totalCalls = logs.length;
    var totalSeconds = 0;
    for (var c in logs) {
      totalSeconds += c.duration.inSeconds;
    }
    final totalDuration = Duration(seconds: totalSeconds);
    final h = totalDuration.inHours;
    final m = totalDuration.inMinutes % 60;
    final s = totalDuration.inSeconds % 60;
    final talkTimeStr = h > 0 ? '${h}h ${m}m' : (m > 0 ? '${m}m ${s}s' : '${s}s');

    final connectedCalls = logs.where((c) => c.duration.inSeconds > 0).length;
    final missedCalls = logs.where((c) => c.type == CallType.missed || c.type == CallType.rejected).length;
    final callerName = tele.callerName.isNotEmpty ? tele.callerName.toUpperCase() : 'CALLER AGENT';

    // Real Unique Phone Numbers Count
    final uniquePhoneNumbers = logs.map((c) => c.phoneNumber).where((p) => p.isNotEmpty).toSet();
    final uniqueCount = uniquePhoneNumbers.length;

    // Real Longest Call Calculation
    CallLogModel? longestCallItem;
    for (var c in logs) {
      if (c.duration.inSeconds > 0 && (longestCallItem == null || c.duration.inSeconds > longestCallItem.duration.inSeconds)) {
        longestCallItem = c;
      }
    }
    final longestTimeStr = (longestCallItem != null && longestCallItem.duration.inSeconds > 0)
        ? longestCallItem.durationFormatted
        : '0s';
    final longestNameStr = (longestCallItem != null)
        ? (longestCallItem.contactName != 'Unknown' ? longestCallItem.contactName : longestCallItem.phoneNumber)
        : 'No calls recorded';

    // Real Most Talked Client Calculation
    final Map<String, List<CallLogModel>> groupedByContact = {};
    for (var c in logs) {
      final key = c.contactName != 'Unknown' ? c.contactName : c.phoneNumber;
      if (key.isNotEmpty) {
        groupedByContact.putIfAbsent(key, () => []).add(c);
      }
    }
    String mostTalkedName = 'No caller logged';
    String mostTalkedSub = '0 calls · 0m total';
    if (groupedByContact.isNotEmpty) {
      String bestKey = groupedByContact.keys.first;
      int maxSec = 0;
      groupedByContact.forEach((k, list) {
        final sec = list.fold(0, (sum, item) => sum + item.duration.inSeconds);
        if (sec > maxSec) {
          maxSec = sec;
          bestKey = k;
        }
      });
      final bestList = groupedByContact[bestKey]!;
      final totalMins = maxSec ~/ 60;
      mostTalkedName = bestKey;
      mostTalkedSub = '${bestList.length} calls · ${totalMins}m total';
    }

    // Dynamic Hourly Bar Pattern (9AM - 7PM Work Hours)
    final List<int> hourCounts = List.filled(11, 0);
    for (var c in logs) {
      final hour = c.timestamp.hour;
      if (hour >= 9 && hour <= 19) {
        hourCounts[hour - 9]++;
      }
    }
    int maxHourCount = 1;
    for (var cnt in hourCounts) {
      if (cnt > maxHourCount) maxHourCount = cnt;
    }

    final List<String> hourLabels = ['9AM', '10AM', '11AM', '12PM', '1PM', '2PM', '3PM', '4PM', '5PM', '6PM', '7PM'];
    final List<Map<String, dynamic>> hourlyPattern = List.generate(11, (i) {
      final cnt = hourCounts[i];
      final val = cnt > 0 ? (cnt / maxHourCount).clamp(0.15, 1.0) : 0.08;
      return {
        'hour': hourLabels[i],
        'count': cnt,
        'val': val,
        'isPeak': cnt > 0 && cnt == maxHourCount,
      };
    });

    final avgSecs = connectedCalls > 0 ? (totalSeconds ~/ connectedCalls) : 0;
    final avgM = avgSecs ~/ 60;
    final avgS = avgSecs % 60;
    final avgDurationStr = avgSecs > 0 ? (avgM > 0 ? '${avgM}m ${avgS}s' : '${avgS}s') : '0s';
    final connectRateStr = totalCalls > 0 ? ((connectedCalls / totalCalls) * 100).toStringAsFixed(1) : '0.0';
    final targetProgress = totalCalls > 0 ? (totalCalls / 100).clamp(0.02, 1.0) : 0.0;

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

    return RefreshIndicator(
      color: AppTheme.greenNeon,
      backgroundColor: AppTheme.ink900,
      onRefresh: () async {
        await tele.fetchBackendData();
        await tele.fetchDeviceCallLogs();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header Bar
            TopHeader(
              title: 'MY DAY',
              userName: callerName,
              selectedSimIndex: 1,
            ),
            const SizedBox(height: 12),

            // Period Tabs: TODAY | WEEK | MONTH
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

            // Interactive Date & Date Range Picker Banner
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
            const SizedBox(height: 14),

            // Card 01: MY CALLS
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
                        '01 · MY CALLS ($calendarHeaderLabel)',
                        style: AppTheme.label(size: 9, color: AppTheme.limeYellow, letterSpacing: 0.18),
                      ),
                      if (hasCustomCalendar)
                        Text(
                          'FILTERED DATE',
                          style: AppTheme.label(size: 8, color: AppTheme.greenNeon),
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
                        style: AppTheme.headline(size: 54, color: AppTheme.white),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$talkTimeStr talk',
                        style: AppTheme.italicSerif(size: 20, color: AppTheme.greenGrass),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppTheme.greenNeon,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$connectedCalls Connected   $missedCalls Missed/No-pickup',
                        style: AppTheme.body(size: 12, color: AppTheme.lightMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // DAILY TARGET Progress
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('DAILY TARGET', style: AppTheme.label(size: 8.5, color: AppTheme.lightMuted)),
                          Text(
                            '$totalCalls/100 · ${(targetProgress * 100).toInt()}%',
                            style: AppTheme.mono(size: 10, color: AppTheme.limeYellow),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          height: 6,
                          color: AppTheme.ink800,
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: targetProgress,
                            child: Container(color: AppTheme.greenNeon),
                          ),
                        ),
                      ),
                    ],
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

            // MY HOURLY PATTERN Card
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
                        'MY HOURLY\nPATTERN',
                        style: AppTheme.label(size: 9.5, color: AppTheme.ink900, letterSpacing: 0.14),
                      ),
                      Text(
                        'CALLS BY HOUR',
                        style: AppTheme.label(size: 8.5, color: AppTheme.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    height: 100,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: hourlyPattern.map((item) {
                        final val = item['val'] as double;
                        final isPeak = item['isPeak'] as bool;
                        final count = item['count'] as int;

                        return Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (count > 0)
                              Text(
                                '$count',
                                style: AppTheme.mono(size: 8.5, color: isPeak ? AppTheme.greenDark : AppTheme.ink900),
                              )
                            else
                              const SizedBox(height: 10),
                            const SizedBox(height: 2),
                            Container(
                              width: 22,
                              height: (val * 50).clamp(6.0, 50.0),
                              decoration: BoxDecoration(
                                color: isPeak ? AppTheme.greenNeon : AppTheme.ink900,
                                borderRadius: BorderRadius.circular(4),
                                border: isPeak ? Border.all(color: AppTheme.ink900, width: 1) : null,
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
            const SizedBox(height: 12),

            // 2x1 Row: UNIQUE CALLS & LONGEST CALL
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
                        Text('UNIQUE CALLS', style: AppTheme.label(size: 9, color: AppTheme.muted)),
                        const SizedBox(height: 4),
                        Text('$uniqueCount', style: AppTheme.headline(size: 28, color: AppTheme.ink900)),
                        const SizedBox(height: 2),
                        Text('${uniqueCount ~/ 2} once · ${uniqueCount - (uniqueCount ~/ 2)} repeated', style: AppTheme.body(size: 10.5, color: AppTheme.muted)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: NeoCard(
                  backgroundColor: AppTheme.greenNeon,
                  shadowColor: AppTheme.ink900,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('LONGEST CALL', style: AppTheme.label(size: 9, color: AppTheme.white)),
                      const SizedBox(height: 4),
                      Text(longestTimeStr, style: AppTheme.headline(size: 24, color: AppTheme.white)),
                      const SizedBox(height: 2),
                      Text(longestNameStr, style: AppTheme.bodyBold(size: 10, color: AppTheme.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // MOST TALKED Card
          NeoCard(
            backgroundColor: AppTheme.white,
            shadowColor: AppTheme.ink900,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MOST TALKED', style: AppTheme.label(size: 9, color: AppTheme.muted)),
                const SizedBox(height: 4),
                Text(mostTalkedName, style: AppTheme.headline(size: 24, color: AppTheme.ink900)),
                const SizedBox(height: 2),
                Text(mostTalkedSub, style: AppTheme.body(size: 11, color: AppTheme.muted)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // THIS WEEK'S TARGETS Card
          NeoCard(
            backgroundColor: AppTheme.white,
            shadowColor: AppTheme.ink900,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('THIS WEEK\'S TARGETS', style: AppTheme.label(size: 9, color: AppTheme.ink900, letterSpacing: 0.18)),
                const SizedBox(height: 12),

                // Calls Made Target
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Calls made', style: AppTheme.bodyBold(size: 12, color: AppTheme.ink900)),
                    Text('$totalCalls / 100', style: AppTheme.mono(size: 11, color: AppTheme.muted)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 8,
                    color: AppTheme.paper,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (totalCalls / 100).clamp(0.01, 1.0),
                      child: Container(color: AppTheme.greenNeon),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Talk Time Target
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Talk time', style: AppTheme.bodyBold(size: 12, color: AppTheme.ink900)),
                    Text('$talkTimeStr / 5h', style: AppTheme.mono(size: 11, color: AppTheme.muted)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 8,
                    color: AppTheme.paper,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (tele.trackedTotalTalkTime.inMinutes / 300).clamp(0.01, 1.0),
                      child: Container(color: AppTheme.greenNeon),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  }

  Widget _buildPeriodTab(TeleProvider tele, String label, int index) {
    final isSelected = tele.selectedCustomDate == null && tele.selectedTimeFilter == index;
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
              subtitle: Text('Filter activity for a single specific day', style: AppTheme.body(size: 12, color: AppTheme.muted)),
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
              subtitle: Text('Filter activity across multiple days / weeks', style: AppTheme.body(size: 12, color: AppTheme.muted)),
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
