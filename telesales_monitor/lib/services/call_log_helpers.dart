import 'package:intl/intl.dart';

import '../models/call_log_model.dart';

/// Filters of the in-app call log (Dialer tab → CALL LOG).
enum CallLogFilter { all, missed, incoming, outgoing }

extension CallLogFilterLabel on CallLogFilter {
  String get label => switch (this) {
    CallLogFilter.all => 'ALL',
    CallLogFilter.missed => 'MISSED',
    CallLogFilter.incoming => 'INCOMING',
    CallLogFilter.outgoing => 'OUTGOING',
  };
}

/// Calls the customer made that nobody talked on: missed, rejected or never answered.
bool isMissedCall(CallLogModel c) =>
    c.type == CallType.missed ||
    c.type == CallType.rejected ||
    c.type == CallType.neverAttended ||
    (c.type == CallType.incoming && c.duration.inSeconds == 0);

bool matchesCallFilter(CallLogModel c, CallLogFilter f) => switch (f) {
  CallLogFilter.all => true,
  CallLogFilter.missed => isMissedCall(c),
  CallLogFilter.incoming =>
    c.type == CallType.incoming && c.duration.inSeconds > 0,
  CallLogFilter.outgoing => c.type == CallType.outgoing,
};

/// The call's direction as the phone's call log names it: Outgoing, Incoming, Missed or Rejected.
/// An outgoing call nobody answered stays "Outgoing" (its outcome says "Not connected").
String callTypeText(CallLogModel c) {
  if (c.type == CallType.rejected) return 'Rejected';
  if (isMissedCall(c)) return 'Missed';
  return c.type == CallType.outgoing ? 'Outgoing' : 'Incoming';
}

/// What happened on the call, in words: its talk time, or why there was none.
String callOutcome(CallLogModel c) {
  if (c.type == CallType.rejected) return 'Rejected';
  if (c.type == CallType.neverAttended) return 'Not answered';
  if (c.type == CallType.missed) return 'Missed';
  if (c.duration.inSeconds == 0) {
    return c.type == CallType.outgoing ? 'Not connected' : 'Missed';
  }
  return c.durationFormatted;
}

/// True when the call had no conversation (shown in a warning colour).
bool callHadNoTalk(CallLogModel c) =>
    isMissedCall(c) || c.duration.inSeconds == 0;

/// "TODAY", "YESTERDAY", "14 NOV", or "14 NOV 2025" outside the current year.
String callDayLabel(DateTime day, DateTime now) {
  final d = DateTime(day.year, day.month, day.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return 'TODAY';
  if (diff == 1) return 'YESTERDAY';
  return (d.year == now.year ? DateFormat('d MMM') : DateFormat('d MMM y'))
      .format(d)
      .toUpperCase();
}

/// Newest first, one group per calendar day: (day label, calls of that day).
List<(String, List<CallLogModel>)> groupCallsByDay(
  Iterable<CallLogModel> calls,
  DateTime now,
) {
  final sorted = calls.toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  final groups = <(String, List<CallLogModel>)>[];
  DateTime? currentDay;
  for (final c in sorted) {
    final day = DateTime(c.timestamp.year, c.timestamp.month, c.timestamp.day);
    if (currentDay != day) {
      currentDay = day;
      groups.add((callDayLabel(day, now), <CallLogModel>[]));
    }
    groups.last.$2.add(c);
  }
  return groups;
}

/// Calls the server has not acknowledged yet (newer than the last synced call).
int countNotSynced(Iterable<CallLogModel> calls, DateTime? lastAcked) =>
    lastAcked == null
    ? calls.length
    : calls.where((c) => c.timestamp.isAfter(lastAcked)).length;
