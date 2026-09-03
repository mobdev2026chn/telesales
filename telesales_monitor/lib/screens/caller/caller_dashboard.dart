import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../providers/tele_provider.dart';
import 'call_session_screen.dart';

class CallerDashboard extends StatefulWidget {
  const CallerDashboard({super.key});

  @override
  State<CallerDashboard> createState() => _CallerDashboardState();
}

class _CallerDashboardState extends State<CallerDashboard> {
  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);

    final logs = tele.simTrackedCallLogs;
    final totalCalls = logs.length;
    var totalSeconds = 0;
    for (var c in logs) {
      totalSeconds += c.duration.inSeconds;
    }
    final totalDuration = Duration(seconds: totalSeconds);
    final h = totalDuration.inHours;
    final m = totalDuration.inMinutes % 60;
    final talkTimeStr = h > 0 ? '${h}h ${m}m' : '${m}m';

    final connectedCalls = logs.where((c) => c.duration.inSeconds > 0).length;
    final callerName = tele.callerName.isNotEmpty ? tele.callerName.toUpperCase() : 'MUKHIL';
    final initials = callerName.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join('').toUpperCase();

    const targetCalls = 40;
    final targetProgress = (totalCalls / targetCalls).clamp(0.02, 1.0);

    // Callbacks due list
    final callbacks = tele.callbacks;
    final freshCount = tele.leads.where((l) => l.attempts == 0).length;

    // Break / Duty time strings
    final dutyStartStr = DateFormat('h:mm a').format(tele.dutyStartTime);

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
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar: ASKEVA · TELESALES & HELLO, <NAME>. + Avatar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ASKEVA · TELESALES',
                          style: AppTheme.mono(size: 10, color: AppTheme.muted, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'HELLO, $callerName.',
                          style: AppTheme.headline(size: 32, color: AppTheme.ink900),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Green Avatar Circle
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.greenNeon,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.ink900, width: 1.5),
                      boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                    ),
                    child: Center(
                      child: Text(
                        initials.isNotEmpty ? initials : 'MU',
                        style: AppTheme.headline(size: 18, color: AppTheme.ink900),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Status Pills: ON DUTY & TAKE BREAK
              Row(
                children: [
                  GestureDetector(
                    onTap: () => tele.toggleDuty(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: tele.isOnDuty ? AppTheme.greenNeon : AppTheme.paper,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppTheme.ink900, width: 1.5),
                        boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: tele.isOnDuty ? AppTheme.ink900 : AppTheme.muted,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            tele.isOnDuty ? 'ON DUTY · $dutyStartStr' : 'OFF DUTY',
                            style: AppTheme.mono(size: 10, color: AppTheme.ink900, weight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => _showBreakOptions(context, tele),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: tele.isOnBreak ? AppTheme.limeYellow : AppTheme.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppTheme.ink900, width: 1.5),
                        boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                      ),
                      child: Text(
                        tele.isOnBreak ? 'ON BREAK (RESUME)' : 'TAKE BREAK',
                        style: AppTheme.mono(size: 10, color: AppTheme.ink900, weight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Card 1: DAILY TARGET
              NeoCard(
                backgroundColor: AppTheme.ink900,
                shadowColor: AppTheme.ink900,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DAILY TARGET',
                      style: AppTheme.label(size: 9.5, color: AppTheme.greenGrass, letterSpacing: 0.18),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$totalCalls',
                          style: AppTheme.headline(size: 46, color: AppTheme.white),
                        ),
                        Text(
                          '/$targetCalls',
                          style: AppTheme.headline(size: 46, color: AppTheme.greenGrass),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'calls today',
                          style: AppTheme.body(size: 13, color: AppTheme.lightMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Progress Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        height: 8,
                        color: AppTheme.darkGreenBar,
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: targetProgress,
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: AppTheme.greenGradient,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 2x1 Grid: CONNECTED & TALK TIME
              Row(
                children: [
                  Expanded(
                    child: NeoCard(
                      backgroundColor: AppTheme.white,
                      shadowColor: AppTheme.ink900,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CONNECTED',
                            style: AppTheme.label(size: 9, color: AppTheme.muted, letterSpacing: 0.14),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$connectedCalls',
                            style: AppTheme.headline(size: 38, color: AppTheme.ink900),
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
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TALK TIME',
                            style: AppTheme.label(size: 9, color: AppTheme.muted, letterSpacing: 0.14),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            talkTimeStr,
                            style: AppTheme.headline(size: 38, color: AppTheme.ink900),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 7 METRICS PERFORMANCE SUMMARY CARD
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
                        Row(
                          children: [
                            Container(width: 8, height: 8, color: AppTheme.greenNeon),
                            const SizedBox(width: 8),
                            Text(
                              'CALL PERFORMANCE METRICS',
                              style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.16),
                            ),
                          ],
                        ),
                        Text(
                          'TODAY',
                          style: AppTheme.mono(size: 9.5, color: AppTheme.muted, weight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _metricBadge('TOTAL CALLS', '${tele.trackedTotalCalls}', AppTheme.ink900, AppTheme.white),
                        _metricBadge('INCOMING', '${tele.trackedIncomingCalls}', AppTheme.paper, AppTheme.ink900),
                        _metricBadge('OUTGOING', '${tele.trackedOutgoingCalls}', AppTheme.paper, AppTheme.ink900),
                        _metricBadge('MISSED', '${tele.trackedMissedCalls}', AppTheme.redMissed.withValues(alpha: 0.12), AppTheme.redMissed),
                        _metricBadge('REJECTED', '${tele.trackedRejectedCalls}', AppTheme.limeYellow, AppTheme.ink900),
                        _metricBadge('NEVER ATTENDED', '${tele.trackedNeverAttendedCalls}', AppTheme.paper, AppTheme.ink900),
                        _metricBadge('UNIQUE CALLS', '${tele.trackedUniqueCalls}', AppTheme.greenNeon, AppTheme.ink900),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 2x1 Grid: LONGEST CALL & MOST REPEATED CALLS OF THE DAY
              Builder(
                builder: (ctx) {
                  final repeated = tele.mostRepeatedCallToday;
                  final longest = tele.longestCallToday;

                  final longestName = longest != null ? (longest.contactName != 'Unknown' ? longest.contactName : longest.phoneNumber) : 'No calls yet';
                  final longestDur = longest?.durationFormatted ?? '0s';

                  final repeatedName = repeated != null ? (repeated['name']?.toString() ?? 'No repeated calls') : 'No repeated calls';
                  final repeatedCount = repeated != null ? '${repeated['count']}x calls' : '0x calls';
                  final repeatedDur = repeated != null ? (repeated['durationStr']?.toString() ?? '') : '';

                  return Row(
                    children: [
                      Expanded(
                        child: NeoCard(
                          backgroundColor: AppTheme.white,
                          shadowColor: AppTheme.ink900,
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'LONGEST CALL',
                                style: AppTheme.label(size: 8.5, color: AppTheme.muted, letterSpacing: 0.12),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                longestDur,
                                style: AppTheme.headline(size: 24, color: AppTheme.ink900),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                longestName,
                                style: AppTheme.body(size: 11, color: AppTheme.muted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                              Text(
                                'MOST REPEATED',
                                style: AppTheme.label(size: 8.5, color: AppTheme.muted, letterSpacing: 0.12),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Text(
                                    repeatedCount,
                                    style: AppTheme.headline(size: 24, color: AppTheme.greenDark),
                                  ),
                                  if (repeatedDur.isNotEmpty) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      '($repeatedDur)',
                                      style: AppTheme.mono(size: 9, color: AppTheme.muted),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                repeatedName,
                                style: AppTheme.body(size: 11, color: AppTheme.muted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),

              // Card 3: CALLBACKS DUE · X
              NeoCard(
                backgroundColor: AppTheme.white,
                shadowColor: AppTheme.ink900,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CALLBACKS DUE · ${callbacks.isNotEmpty ? callbacks.length : 2}',
                      style: AppTheme.label(size: 9.5, color: AppTheme.ink900, letterSpacing: 0.16),
                    ),
                    const SizedBox(height: 12),

                    // Demo & Actual Callbacks items
                    if (callbacks.isNotEmpty)
                      ...callbacks.take(4).map((cb) {
                        final isOverdue = cb.scheduledTime.isBefore(DateTime.now());
                        final bg = isOverdue ? AppTheme.redOverdue : AppTheme.limeYellow;
                        final fg = isOverdue ? AppTheme.white : AppTheme.ink900;
                        final dateStr = isOverdue
                            ? 'OVERDUE · ${DateFormat('d MMM').format(cb.scheduledTime).toUpperCase()}'
                            : 'TODAY · ${DateFormat('h:mm a').format(cb.scheduledTime).toUpperCase()}';

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GestureDetector(
                            onTap: () {
                              tele.makeDirectCall(cb.phone);
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: AppTheme.ink900, width: 1.5),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      cb.name,
                                      style: AppTheme.bodyBold(size: 13, color: fg),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    dateStr,
                                    style: AppTheme.mono(size: 10, color: fg, weight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      })
                    else ...[
                      // Item 1: Overdue
                      GestureDetector(
                        onTap: () => tele.makeDirectCall('+91 90250 11876'),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.redOverdue,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppTheme.ink900, width: 1.5),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Meenakshi Agencies',
                                style: AppTheme.bodyBold(size: 13, color: AppTheme.white),
                              ),
                              Text(
                                'OVERDUE · 27 AUG',
                                style: AppTheme.mono(size: 10, color: AppTheme.white, weight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Item 2: Today
                      GestureDetector(
                        onTap: () => tele.makeDirectCall('+91 95510 22110'),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.limeYellow,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppTheme.ink900, width: 1.5),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Chennai Silks Outlet',
                                style: AppTheme.bodyBold(size: 13, color: AppTheme.ink900),
                              ),
                              Text(
                                'TODAY · 4:00 PM',
                                style: AppTheme.mono(size: 10, color: AppTheme.ink900, weight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Bottom Big CTA: START CALL SESSION · X FRESH
              GestureDetector(
                onTap: () {
                  tele.startCallSession();
                  CallSessionScreen.push(context);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.ink900,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppTheme.ink900, width: 1.5),
                    boxShadow: AppTheme.neoShadow(color: AppTheme.ink900, offset: 4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.play_arrow_rounded, color: AppTheme.greenGrass, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        'START CALL SESSION · ${freshCount > 0 ? freshCount : 5} FRESH',
                        style: AppTheme.label(size: 11.5, color: AppTheme.greenGrass, letterSpacing: 0.16),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBreakOptions(BuildContext context, TeleProvider tele) {
    if (tele.isOnBreak) {
      tele.endBreak();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.ink900,
          content: Text('✓ Welcome back! Break ended.', style: AppTheme.bodyBold(size: 12, color: AppTheme.greenNeon)),
        ),
      );
      return;
    }

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
            Text('SELECT BREAK TYPE', style: AppTheme.headline(size: 18, color: AppTheme.ink900)),
            const SizedBox(height: 14),
            ListTile(
              title: Text('☕ Tea Break (10-15 min)', style: AppTheme.bodyBold(size: 14)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.ink900, width: 1.5),
              ),
              tileColor: AppTheme.white,
              onTap: () {
                Navigator.pop(ctx);
                tele.startBreak('Tea break');
              },
            ),
            const SizedBox(height: 10),
            ListTile(
              title: Text('🍽️ Lunch Break (30-45 min)', style: AppTheme.bodyBold(size: 14)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.ink900, width: 1.5),
              ),
              tileColor: AppTheme.white,
              onTap: () {
                Navigator.pop(ctx);
                tele.startBreak('Lunch');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricBadge(String label, String value, Color bg, Color textCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.ink900, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTheme.label(
              size: 8,
              color: textCol == AppTheme.white ? AppTheme.limeYellow : AppTheme.muted,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTheme.headline(size: 18, color: textCol),
          ),
        ],
      ),
    );
  }
}
