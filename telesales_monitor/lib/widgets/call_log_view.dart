import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/call_log_model.dart';
import '../providers/tele_provider.dart';
import '../services/api_parsers.dart';
import '../services/call_log_helpers.dart';
import '../theme/app_theme.dart';
import 'contact_history_sheet.dart';

/// The in-app call log (Dialer tab → CALL LOG): the work-SIM calls AskEVA tracks and sends to the
/// admin, newest first, by day. Tap a call for that contact's history (call back, WhatsApp,
/// follow-up); the phone button calls back on the work SIM. Personal-SIM calls never appear.
class CallLogView extends StatefulWidget {
  const CallLogView({super.key});

  @override
  State<CallLogView> createState() => _CallLogViewState();
}

class _CallLogViewState extends State<CallLogView> {
  CallLogFilter _filter = CallLogFilter.all;

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);
    final calls = tele.allCallLogs;
    final shown = calls.where((c) => matchesCallFilter(c, _filter));
    final groups = groupCallsByDay(shown, DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _syncLine(tele, calls),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final f in CallLogFilter.values) ...[
                _FilterChip(
                  label: f.label,
                  count: calls.where((c) => matchesCallFilter(c, f)).length,
                  selected: _filter == f,
                  onTap: () => setState(() => _filter = f),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.greenNeon,
            backgroundColor: AppTheme.ink900,
            onRefresh: tele.fetchDeviceCallLogs,
            child: groups.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [_empty(calls.isEmpty)],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      for (final (label, dayCalls) in groups) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 8),
                          child: Text(
                            '$label · ${dayCalls.length}',
                            style: AppTheme.label(
                              size: 9.5,
                              color: AppTheme.ink700,
                              letterSpacing: 0.14,
                            ),
                          ),
                        ),
                        for (final c in dayCalls)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _CallRow(
                              call: c,
                              onOpen: () => _openHistory(context, c, calls),
                              onCall: () => tele.makeDirectCall(c.phoneNumber),
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  /// Which calls this is, and whether the admin already has them.
  Widget _syncLine(TeleProvider tele, List<CallLogModel> calls) {
    final since = tele.loginSessionTimestamp;
    final scope = [
      'WORK SIM ${tele.workSimSlotIndex + 1}',
      if (since != null)
        'SINCE ${DateFormat('d MMM').format(since).toUpperCase()}',
    ].join(' · ');
    final waiting = tele.unsyncedCallCount;
    final synced = waiting == 0;
    return Row(
      children: [
        Expanded(
          child: Text(
            scope,
            style: AppTheme.mono(
              size: 10,
              color: AppTheme.muted,
              weight: FontWeight.w700,
            ),
          ),
        ),
        if (calls.isNotEmpty)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                synced ? Icons.cloud_done_rounded : Icons.cloud_upload_rounded,
                size: 14,
                color: synced ? AppTheme.greenDark : AppTheme.orangePill,
              ),
              const SizedBox(width: 4),
              Text(
                synced ? 'ALL SENT TO ADMIN' : '$waiting WAITING TO SEND',
                style: AppTheme.label(
                  size: 9,
                  color: synced ? AppTheme.greenDark : AppTheme.orangePill,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _empty(bool noCallsAtAll) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 12),
      child: Column(
        children: [
          const Icon(Icons.history_rounded, size: 36, color: AppTheme.ink700),
          const SizedBox(height: 10),
          Text(
            noCallsAtAll
                ? 'No work calls yet'
                : 'No ${_filter.label.toLowerCase()} calls',
            style: AppTheme.bodyBold(size: 14, color: AppTheme.ink900),
          ),
          const SizedBox(height: 4),
          Text(
            'Calls on your work SIM since you logged in show here. Pull down to refresh.',
            textAlign: TextAlign.center,
            style: AppTheme.body(size: 12, color: AppTheme.ink700),
          ),
        ],
      ),
    );
  }

  void _openHistory(
    BuildContext context,
    CallLogModel c,
    List<CallLogModel> calls,
  ) {
    final sameNumber =
        calls.where((o) => samePhone(o.phoneNumber, c.phoneNumber)).toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    ContactHistorySheet.show(context, {
      'name': _displayName(c),
      'phone': c.phoneNumber,
      'rawLogs': sameNumber,
    });
  }
}

String _displayName(CallLogModel c) {
  final name = c.contactName.trim();
  return name.isEmpty || name.toLowerCase() == 'unknown' ? c.phoneNumber : name;
}

class _CallRow extends StatelessWidget {
  const _CallRow({
    required this.call,
    required this.onOpen,
    required this.onCall,
  });

  final CallLogModel call;
  final VoidCallback onOpen;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final c = call;
    final missed = isMissedCall(c);
    final noTalk = callHadNoTalk(c);
    final name = _displayName(c);
    final IconData icon;
    final Color iconColor;
    if (c.type == CallType.rejected) {
      icon = Icons.call_end_rounded;
      iconColor = AppTheme.redMissed;
    } else if (missed) {
      icon = Icons.call_missed_rounded;
      iconColor = AppTheme.redMissed;
    } else if (c.type == CallType.outgoing) {
      icon = Icons.call_made_rounded;
      iconColor = AppTheme.ink900;
    } else {
      icon = Icons.call_received_rounded;
      iconColor = AppTheme.greenDark;
    }

    return Material(
      color: AppTheme.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTheme.ink900, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.paper,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.ink900, width: 1),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyBold(
                        size: 14,
                        color: missed ? AppTheme.redMissed : AppTheme.ink900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // "OUTGOING · 04:30 PM", like the phone's own call log
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: callTypeText(c).toUpperCase(),
                            style: AppTheme.label(
                              size: 9.5,
                              color: iconColor,
                              letterSpacing: 0.08,
                            ),
                          ),
                          TextSpan(
                            text:
                                '  ·  ${DateFormat('hh:mm a').format(c.timestamp)}',
                            style: AppTheme.mono(
                              size: 10.5,
                              color: AppTheme.ink700,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (name != c.phoneNumber) ...[
                      const SizedBox(height: 2),
                      Text(
                        c.phoneNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.mono(
                          size: 10.5,
                          color: AppTheme.ink700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                callOutcome(c),
                style: AppTheme.mono(
                  size: 11,
                  color: noTalk ? AppTheme.orangePill : AppTheme.ink900,
                  weight: FontWeight.w700,
                ),
              ),
              IconButton(
                onPressed: onCall,
                tooltip: 'Call back',
                icon: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppTheme.greenNeon,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.ink900, width: 1.2),
                  ),
                  child: const Icon(
                    Icons.phone_rounded,
                    size: 17,
                    color: AppTheme.ink900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.limeYellow : AppTheme.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppTheme.ink900, width: 1.2),
        ),
        child: Text(
          '$label · $count',
          style: AppTheme.label(size: 9.5, color: AppTheme.ink900),
        ),
      ),
    );
  }
}
