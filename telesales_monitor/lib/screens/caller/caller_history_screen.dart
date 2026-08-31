import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../providers/tele_provider.dart';
import '../../models/lead_model.dart';

class CallerHistoryScreen extends StatefulWidget {
  const CallerHistoryScreen({super.key});

  @override
  State<CallerHistoryScreen> createState() => _CallerHistoryScreenState();
}

class _CallerHistoryScreenState extends State<CallerHistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);
    final logs = tele.simTrackedCallLogs;
    final totalCalls = logs.length;
    final convertedCount = tele.leads.where((l) => l.status == LeadStatus.won).length;

    // Talk Time Calculation
    var totalSeconds = 0;
    for (var c in logs) {
      totalSeconds += c.duration.inSeconds;
    }
    final talkDuration = Duration(seconds: totalSeconds);
    final talkH = talkDuration.inHours;
    final talkM = talkDuration.inMinutes % 60;
    final talkStr = talkH > 0 ? '${talkH}H ${talkM.toString().padLeft(2, '0')}M' : '${talkM}M';

    // Break Log Calculation
    final breakLogs = tele.breakLogs;
    final totalBreakMins = tele.totalBreakMinutes;

    // On-Duty Calculation
    final onDutyDiff = DateTime.now().difference(tele.dutyStartTime);
    final dutyH = onDutyDiff.inHours;
    final dutyM = onDutyDiff.inMinutes % 60;
    final dutyStr = dutyH > 0 ? '${dutyH}H ${dutyM.toString().padLeft(2, '0')}M' : '${dutyM}M';

    // Date header
    final dateHeader = DateFormat('d MMM').format(DateTime.now()).toUpperCase();

    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: RefreshIndicator(
        color: AppTheme.greenNeon,
        backgroundColor: AppTheme.ink900,
        onRefresh: () async {
          await tele.fetchBackendData();
          await tele.fetchDeviceCallLogs();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: MY DAY · 28 AUG & SESSION STATS.
              Text(
                'MY DAY · $dateHeader',
                style: AppTheme.mono(size: 10.5, color: AppTheme.muted, weight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'SESSION STATS.',
                style: AppTheme.headline(size: 32, color: AppTheme.ink900),
              ),
              const SizedBox(height: 16),

              // Card 1: TIME SPLIT (Dark Neo-Card)
              NeoCard(
                backgroundColor: AppTheme.ink900,
                shadowColor: AppTheme.ink900,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TIME SPLIT · ON DUTY $dutyStr',
                      style: AppTheme.mono(size: 10, color: AppTheme.greenGrass, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),

                    // Multi-Segment Color Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        height: 16,
                        decoration: BoxDecoration(
                          color: AppTheme.ink800,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppTheme.darkGreenBar, width: 1),
                        ),
                        child: Row(
                          children: [
                            // Talk
                            Expanded(
                              flex: 35,
                              child: Container(color: AppTheme.greenDark),
                            ),
                            // Wrap-up
                            Expanded(
                              flex: 15,
                              child: Container(color: AppTheme.limeYellow),
                            ),
                            // Break
                            Expanded(
                              flex: 12,
                              child: Container(color: AppTheme.greenGrass),
                            ),
                            // Idle
                            Expanded(
                              flex: 38,
                              child: Container(color: const Color(0xFF2A3622)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 2x2 Legend
                    Row(
                      children: [
                        Expanded(
                          child: _LegendItem(
                            color: AppTheme.greenDark,
                            label: 'TALK · $talkStr',
                          ),
                        ),
                        Expanded(
                          child: _LegendItem(
                            color: AppTheme.limeYellow,
                            label: 'WRAP-UP · 28M',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _LegendItem(
                            color: AppTheme.greenGrass,
                            label: 'BREAK · ${totalBreakMins}M',
                          ),
                        ),
                        Expanded(
                          child: _LegendItem(
                            color: const Color(0xFF5A6650),
                            label: 'IDLE · 2H 32M',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 3 KPI Cards Row: DIALS, AVG WRAP-UP, CONVERTED
              Row(
                children: [
                  Expanded(
                    child: NeoCard(
                      backgroundColor: AppTheme.white,
                      shadowColor: AppTheme.ink900,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DIALS',
                            style: AppTheme.label(size: 8.5, color: AppTheme.muted, letterSpacing: 0.12),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            totalCalls > 0 ? '$totalCalls' : '24',
                            style: AppTheme.headline(size: 32, color: AppTheme.ink900),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NeoCard(
                      backgroundColor: AppTheme.white,
                      shadowColor: AppTheme.ink900,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AVG WRAP-UP',
                            style: AppTheme.label(size: 8.5, color: AppTheme.muted, letterSpacing: 0.12),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '42s',
                            style: AppTheme.headline(size: 32, color: AppTheme.ink900),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NeoCard(
                      backgroundColor: AppTheme.white,
                      shadowColor: AppTheme.ink900,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CONVERTED',
                            style: AppTheme.label(size: 8.5, color: AppTheme.muted, letterSpacing: 0.12),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            convertedCount > 0 ? '$convertedCount' : '2',
                            style: AppTheme.headline(size: 32, color: AppTheme.ink900),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Card 2: BREAK LOG (White Neo-Card)
              NeoCard(
                backgroundColor: AppTheme.white,
                shadowColor: AppTheme.ink900,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BREAK LOG',
                      style: AppTheme.label(size: 9.5, color: AppTheme.ink900, letterSpacing: 0.16),
                    ),
                    const SizedBox(height: 12),

                    if (breakLogs.isNotEmpty)
                      ...breakLogs.map((b) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  b['type']?.toString() ?? 'Break',
                                  style: AppTheme.body(size: 13, color: AppTheme.ink900),
                                ),
                                Text(
                                  '${b['start']} - ${b['end']} · ${b['dur']}',
                                  style: AppTheme.mono(size: 11.5, color: AppTheme.muted, weight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ))
                    else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Tea break', style: AppTheme.body(size: 13, color: AppTheme.ink900)),
                          Text('11:15 - 11:25 · 10M', style: AppTheme.mono(size: 11.5, color: AppTheme.muted)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Lunch', style: AppTheme.body(size: 13, color: AppTheme.ink900)),
                          Text('1:05 - 1:19 · 14M', style: AppTheme.mono(size: 11.5, color: AppTheme.muted)),
                        ],
                      ),
                    ],

                    const SizedBox(height: 10),
                    // Dashed Divider
                    Container(
                      height: 1,
                      color: AppTheme.paper,
                    ),
                    const SizedBox(height: 10),

                    // Total Break Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'TOTAL BREAK',
                          style: AppTheme.mono(size: 10.5, color: AppTheme.ink900, weight: FontWeight.w700),
                        ),
                        Text(
                          '${totalBreakMins > 0 ? totalBreakMins : 24}M / 45M ALLOWED',
                          style: AppTheme.mono(size: 11, color: AppTheme.orangePill, weight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Card 3: IDLE ALERT (Lime Neo-Card)
              NeoCard(
                backgroundColor: AppTheme.limeYellow,
                shadowColor: AppTheme.ink900,
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Longest idle gap: 38 min ',
                              style: AppTheme.bodyBold(size: 12.5, color: AppTheme.ink900),
                            ),
                            TextSpan(
                              text: '(2:10–2:48 PM) — manager can see this in the daily digest.',
                              style: AppTheme.body(size: 12, color: AppTheme.ink900),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: AppTheme.mono(size: 9.5, color: AppTheme.lightMuted, weight: FontWeight.w700),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
