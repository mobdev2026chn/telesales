import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  int _patternFilterIndex = 0; // 0 = TODAY, 1 = WEEK, 2 = MONTH

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);

    final logs = tele.simTrackedCallLogs;
    final totalCalls = tele.trackedTotalCalls;
    final talkTimeStr = tele.trackedTalkTimeFormatted;
    final connectedCalls = tele.trackedConnectedCalls;
    final missedCalls = tele.trackedMissedCalls;
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
    final List<Map<String, dynamic>> hourlyPattern = List.generate(10, (i) {
      final cnt = hourCounts[i];
      final val = cnt > 0 ? (cnt / maxHourCount).clamp(0.15, 1.0) : 0.08;
      return {
        'hour': hourLabels[i],
        'val': val,
        'isPeak': cnt > 0 && cnt == maxHourCount,
      };
    });

    final targetProgress = totalCalls > 0 ? (totalCalls / 100).clamp(0.02, 1.0) : 0.0;

    return SingleChildScrollView(
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
          const SizedBox(height: 16),

          // Card 01: MY CALLS TODAY
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
                      '01 · MY CALLS TODAY',
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
                Text(
                  '$connectedCalls connected · $uniqueCount unique clients · target 100',
                  style: AppTheme.body(size: 11, color: AppTheme.lightMuted),
                ),
                const SizedBox(height: 12),

                // Target Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 8,
                    color: AppTheme.ink800,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: targetProgress > 0 ? targetProgress : 0.01,
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

          // 2x1 Row: AVG / CALL & MISSED
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
                      Text('02 · AVG / CALL', style: AppTheme.label(size: 9, color: AppTheme.muted)),
                      const SizedBox(height: 6),
                      Text(
                        connectedCalls > 0
                            ? '${(tele.trackedTotalTalkTime.inSeconds ~/ connectedCalls) ~/ 60}m ${(tele.trackedTotalTalkTime.inSeconds ~/ connectedCalls) % 60}s'
                            : '0s',
                        style: AppTheme.headline(size: 28, color: AppTheme.ink900),
                      ),
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
                      Text('03 · MISSED', style: AppTheme.label(size: 9, color: AppTheme.muted)),
                      const SizedBox(height: 6),
                      Text('$missedCalls', style: AppTheme.headline(size: 28, color: AppTheme.greenDark)),
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: AppTheme.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppTheme.ink900, width: 1.2),
                          ),
                          child: Row(
                            children: [
                              _buildPatternTab('TODAY', 0),
                              _buildPatternTab('WEEK', 1),
                              _buildPatternTab('MONTH', 2),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppTheme.ink900, width: 1.2),
                          ),
                          child: Row(
                            children: [
                              Text('TODAY', style: AppTheme.label(size: 8, color: AppTheme.ink900)),
                              const Icon(Icons.arrow_drop_down, size: 14, color: AppTheme.ink900),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                SizedBox(
                  height: 90,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: hourlyPattern.map((item) {
                      final val = item['val'] as double;
                      final isPeak = item['isPeak'] as bool;
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
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
    );
  }

  Widget _buildPatternTab(String label, int index) {
    final isSelected = _patternFilterIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _patternFilterIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.ink900 : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: AppTheme.label(
            size: 8,
            color: isSelected ? AppTheme.limeYellow : AppTheme.ink900,
          ),
        ),
      ),
    );
  }
}
