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
    final dutyStart = tele.dutyStartTime;
    final onDutyDiff = dutyStart != null ? DateTime.now().difference(dutyStart) : Duration.zero;
    final dutyH = onDutyDiff.inHours;
    final dutyM = onDutyDiff.inMinutes % 60;
    final dutyStr = dutyStart == null ? '—' : (dutyH > 0 ? '${dutyH}H ${dutyM.toString().padLeft(2, '0')}M' : '${dutyM}M');

    // Real split of the duty time: talk (device call log), breaks (logged), everything else
    final dutySecs = onDutyDiff.inSeconds;
    final breakSecs = totalBreakMins * 60;
    final talkSecs = dutySecs > 0 ? totalSeconds.clamp(0, dutySecs) : totalSeconds;
    final otherSecs = (dutySecs - talkSecs - breakSecs).clamp(0, 1 << 31);
    final otherDur = Duration(seconds: otherSecs);
    final otherStr = dutyStart == null
        ? '—'
        : (otherDur.inHours > 0 ? '${otherDur.inHours}H ${(otherDur.inMinutes % 60).toString().padLeft(2, '0')}M' : '${otherDur.inMinutes}M');
    final connected = logs.where((c) => c.duration.inSeconds > 0).length;
    final avgTalk = connected == 0 ? null : Duration(seconds: totalSeconds ~/ connected);
    final avgTalkStr = avgTalk == null ? '—' : (avgTalk.inMinutes > 0 ? '${avgTalk.inMinutes}m ${avgTalk.inSeconds % 60}s' : '${avgTalk.inSeconds}s');
    int flexOf(int secs) => secs <= 0 ? 0 : (secs * 1000 ~/ (dutySecs > 0 ? dutySecs : (talkSecs + breakSecs).clamp(1, 1 << 31))).clamp(1, 1000);

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
                            if (flexOf(talkSecs) > 0)
                              Expanded(flex: flexOf(talkSecs), child: Container(color: AppTheme.greenDark)),
                            if (flexOf(breakSecs) > 0)
                              Expanded(flex: flexOf(breakSecs), child: Container(color: AppTheme.greenGrass)),
                            if (flexOf(otherSecs) > 0)
                              Expanded(flex: flexOf(otherSecs), child: Container(color: const Color(0xFF2A3622))),
                            if (flexOf(talkSecs) + flexOf(breakSecs) + flexOf(otherSecs) == 0)
                              const Expanded(child: SizedBox()),
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
                            color: const Color(0xFF5A6650),
                            label: 'OTHER · $otherStr',
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
                        const Expanded(child: SizedBox()),
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
                            '$totalCalls',
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
                            'AVG TALK',
                            style: AppTheme.label(size: 8.5, color: AppTheme.muted, letterSpacing: 0.12),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            avgTalkStr,
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
                            '$convertedCount',
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
                    else
                      Text('No breaks taken yet.', style: AppTheme.body(size: 12, color: AppTheme.muted)),

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
                          '${totalBreakMins}M / 45M ALLOWED',
                          style: AppTheme.mono(size: 11, color: AppTheme.orangePill, weight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

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
