import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../providers/tele_provider.dart';
import '../setup/call_recording_setup_screen.dart';
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

    // Today's numbers (the target is per day), counted the same way as the metrics card and the admin web
    final totalCalls = tele.todayTotalCalls;
    final totalDuration = tele.todayTalkTime;
    final h = totalDuration.inHours;
    final m = totalDuration.inMinutes % 60;
    final s = totalDuration.inSeconds % 60;
    final talkTimeStr = h > 0 ? '${h}h ${m}m' : (m > 0 ? '${m}m ${s}s' : '${s}s');

    final connectedCalls = tele.todayConnectedCalls;
    final recordingProblem = tele.recordingProblem;
    final callerName = tele.callerName.isNotEmpty ? tele.callerName.toUpperCase() : '—';
    final initials = callerName.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join('').toUpperCase();

    final targetCalls = tele.dailyTarget;
    final targetProgress = (totalCalls / targetCalls).clamp(0.02, 1.0);

    // Callbacks due list
    final callbacks = tele.callbacks;
    final sessionLeads = tele.callableSessionLeads;
    final freshCount = sessionLeads.where((l) => l.attempts == 0).length;

    // Break / Duty time strings
    final dutyStart = tele.dutyStartTime;
    final dutyStartStr = dutyStart != null ? DateFormat('h:mm a').format(dutyStart) : '—';

    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: RefreshIndicator(
        color: AppTheme.greenNeon,
        backgroundColor: AppTheme.ink900,
        onRefresh: () async {
          await tele.fetchDeviceCallLogs();
          await tele.refreshProfile();
          await tele.fetchBackendData();
          await tele.refreshRecordingSetupStatus();
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
                        initials.isNotEmpty && initials != '—' ? initials : '—',
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

              // Calls are not being recorded with sound: say why and how to fix it
              if (recordingProblem != null) ...[
                GestureDetector(
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CallRecordingSetupScreen()),
                    );
                    await tele.refreshRecordingSetupStatus();
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.redOverdue,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.ink900, width: 1.5),
                      boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.mic_off_rounded, color: AppTheme.white, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('CALLS ARE NOT BEING RECORDED',
                                  style: AppTheme.label(size: 9.5, color: AppTheme.white, letterSpacing: 0.14)),
                              const SizedBox(height: 4),
                              Text(recordingProblem, style: AppTheme.body(size: 12, color: AppTheme.white)),
                              const SizedBox(height: 4),
                              Text('TAP TO FIX →', style: AppTheme.mono(size: 10, color: AppTheme.white, weight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],

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
                          tele.selectedPeriodLabel,
                          style: AppTheme.mono(size: 9.5, color: AppTheme.muted, weight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _metricBadge('TOTAL CALLS', '${tele.totalCalls}', AppTheme.ink900, AppTheme.white),
                        _metricBadge('INCOMING', '${tele.incomingCalls}', AppTheme.paper, AppTheme.ink900),
                        _metricBadge('OUTGOING', '${tele.outgoingCalls}', AppTheme.paper, AppTheme.ink900),
                        _metricBadge('MISSED', '${tele.missedCalls}', AppTheme.redMissed.withValues(alpha: 0.12), AppTheme.redMissed),
                        _metricBadge('REJECTED', '${tele.rejectedCalls}', AppTheme.limeYellow, AppTheme.ink900),
                        _metricBadge('NEVER ATTENDED', '${tele.neverAttendedCalls}', AppTheme.paper, AppTheme.ink900),
                        _metricBadge('UNIQUE CALLS', '${tele.uniqueCalls}', AppTheme.greenNeon, AppTheme.ink900),
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
                      'CALLBACKS DUE · ${callbacks.length}',
                      style: AppTheme.label(size: 9.5, color: AppTheme.ink900, letterSpacing: 0.16),
                    ),
                    const SizedBox(height: 12),

                    // Demo & Actual Callbacks items
                    if (callbacks.isNotEmpty)
                      ...callbacks.take(4).map((cb) {
                        final isOverdue = cb.scheduledTime.isBefore(DateTime.now());
                        final bg = isOverdue ? AppTheme.redOverdue : AppTheme.limeYellow;
                        final fg = isOverdue ? AppTheme.white : AppTheme.ink900;
                        final now = DateTime.now();
                        final isToday = cb.scheduledTime.year == now.year &&
                            cb.scheduledTime.month == now.month &&
                            cb.scheduledTime.day == now.day;
                        final dateStr = isOverdue
                            ? 'OVERDUE · ${DateFormat('d MMM').format(cb.scheduledTime).toUpperCase()}'
                            : isToday
                                ? 'TODAY · ${DateFormat('h:mm a').format(cb.scheduledTime).toUpperCase()}'
                                : DateFormat('d MMM · h:mm a').format(cb.scheduledTime).toUpperCase();

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
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          'No callbacks scheduled. Callbacks you set after a call will appear here.',
                          style: AppTheme.body(size: 12, color: AppTheme.muted),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Bottom Big CTA: START CALL SESSION · X FRESH
              GestureDetector(
                onTap: () {
                  if (sessionLeads.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: AppTheme.ink900,
                        content: Text('No leads assigned to you yet. Ask your manager to assign leads.',
                            style: AppTheme.bodyBold(size: 12, color: AppTheme.limeYellow)),
                      ),
                    );
                    return;
                  }
                  tele.startCallSession();
                  if (tele.activeCallLead != null) CallSessionScreen.push(context);
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
                        sessionLeads.isEmpty ? 'NO LEADS ASSIGNED' : 'START CALL SESSION · $freshCount FRESH',
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
