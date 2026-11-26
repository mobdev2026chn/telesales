// Pure JSON / domain helpers shared by ApiService and TeleProvider.
// No Flutter bindings, no I/O: everything here is covered by unit tests in test/.

import '../models/call_log_model.dart';
import '../models/employee_model.dart';
import '../models/lead_model.dart';
import '../models/recording_model.dart';

/// JSON numbers may arrive as int, double or numeric strings. Never throws.
/// Daily call target when none is set (same default as the server).
const int kDefaultDailyTarget = 250;

int asInt(dynamic v, [int fallback = 0]) {
  if (v is num) return v.toInt();
  if (v is String) return num.tryParse(v.trim())?.toInt() ?? fallback;
  return fallback;
}

String asString(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  final s = v.toString();
  return s.isEmpty ? fallback : s;
}

bool asBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes' || s == 'y') return true;
    if (s == 'false' || s == '0' || s == 'no' || s == 'n') return false;
  }
  return fallback;
}

DateTime? parseServerDate(dynamic v) {
  if (v == null) return null;
  final parsed = DateTime.tryParse(v.toString());
  return parsed?.toLocal();
}

/// Digits only, last 10 digits (Indian mobile). Empty when there are no digits.
String last10Digits(String? phone) {
  final clean = (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  return clean.length > 10 ? clean.substring(clean.length - 10) : clean;
}

/// True only when both numbers have a full 10-digit tail and those tails are identical.
bool samePhone(String? a, String? b) {
  final x = last10Digits(a);
  final y = last10Digits(b);
  return x.length == 10 && x == y;
}

// ---------------------------------------------------------------- Lead status

/// The app calls the server status `new` "newLead" locally.
String leadStatusToWire(LeadStatus s) => s == LeadStatus.newLead ? 'new' : s.name;

LeadStatus leadStatusFromWire(String? wire, {LeadStatus fallback = LeadStatus.newLead}) {
  final s = (wire ?? '').trim();
  if (s.isEmpty) return fallback;
  if (s == 'new' || s == 'newLead') return LeadStatus.newLead;
  for (final v in LeadStatus.values) {
    if (v.name == s) return v;
  }
  // Tolerate case differences ("FOLLOWUP", "followup")
  final lower = s.toLowerCase();
  for (final v in LeadStatus.values) {
    if (v.name.toLowerCase() == lower) return v;
  }
  return fallback;
}

LeadModel leadFromJson(Map<String, dynamic> l) {
  final created = parseServerDate(l['createdAt']);
  final lastCall = parseServerDate(l['lastCallDate']) ?? parseServerDate(l['updatedAt']) ?? created;
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  return LeadModel(
    id: asString(l['id'] ?? l['_id']),
    name: asString(l['name']),
    phone: asString(l['phone']),
    status: leadStatusFromWire(l['status']?.toString()),
    attempts: asInt(l['attempts']),
    note: asString(l['notes'] ?? l['note']),
    lastCallDate: lastCall ?? epoch,
    dateAdded: created ?? epoch,
    assignedTo: asString(l['assignedCaller']),
    assignedCallerId: asString(l['assignedCallerId']),
  );
}

// ---------------------------------------------------------------- Employees

EmployeeModel employeeFromJson(Map<String, dynamic> e) {
  final managerId = asString(e['managerId'] ?? e['reportingManagerId']);
  return EmployeeModel(
    id: asString(e['id'] ?? e['_id']),
    name: asString(e['name']),
    phone: asString(e['phone']),
    role: asString(e['role'], 'caller'),
    team: asString(e['team']),
    avatarUrl: e['avatarUrl']?.toString(),
    photoBase64: e['photoBase64']?.toString(),
    reportingManagerId: managerId.isEmpty ? null : managerId,
    totalCalls: asInt(e['totalCalls']),
    connectedCalls: asInt(e['connectedCalls']),
    totalTalkTime: Duration(seconds: asInt(e['talkTimeSeconds'])),
    incomingCalls: asInt(e['incomingCalls']),
    outgoingCalls: asInt(e['outgoingCalls']),
    missedCalls: asInt(e['missedCalls']),
    neverAttendedCalls: asInt(e['neverAttendedCalls']),
    rank: asInt(e['rank']),
    dailyTarget: asInt(e['dailyTarget'], kDefaultDailyTarget) > 0 ? asInt(e['dailyTarget'], kDefaultDailyTarget) : kDefaultDailyTarget,
  );
}

// ---------------------------------------------------------------- Recordings

/// Absolute URL for a server-relative path like `/api/recordings/<id>/audio`.
String absoluteServerUrl(String raw, String baseUrl) {
  if (raw.isEmpty || !raw.startsWith('/')) return raw;
  final uri = Uri.tryParse(baseUrl);
  if (uri == null || uri.host.isEmpty) return '$baseUrl$raw';
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port$raw';
}

/// Media players cannot send headers: the contract accepts `?token=` on audio URLs.
String withTokenQuery(String url, String token) {
  if (url.isEmpty || token.isEmpty || !url.startsWith('http')) return url;
  if (url.contains('token=')) return url;
  return url.contains('?') ? '$url&token=${Uri.encodeQueryComponent(token)}' : '$url?token=${Uri.encodeQueryComponent(token)}';
}

RecordingModel recordingFromJson(Map<String, dynamic> r, String baseUrl) {
  final started = parseServerDate(r['callStartedAt']);
  final created = parseServerDate(r['createdAt']);
  return RecordingModel(
    id: asString(r['id'] ?? r['_id']),
    agentName: asString(r['callerName'], '—'),
    clientName: asString(r['contactName'], 'Unknown'),
    clientPhone: asString(r['phoneNumber']),
    date: started ?? created ?? DateTime.fromMillisecondsSinceEpoch(0),
    duration: Duration(seconds: asInt(r['durationSeconds'])),
    audioUrl: absoluteServerUrl(asString(r['audioUrl']), baseUrl),
    fileName: asString(r['fileName']),
    note: asString(r['transcript']),
    rating: asInt(r['rating']),
    comment: asString(r['comment']),
    commentedBy: asString(r['commentedBy']),
    pinned: asBool(r['pinned']),
  );
}

// ---------------------------------------------------------------- Calls

CallType callTypeFromNative(String? s) {
  switch (s) {
    case 'outgoing':
      return CallType.outgoing;
    case 'missed':
      return CallType.missed;
    case 'rejected':
      return CallType.rejected;
    default:
      return CallType.incoming;
  }
}

/// How far before the last acknowledged call the sync looks again. Android writes a call to the
/// log when it ends, stamped with its START time: a long call that ends after a later, shorter
/// call was already sent would otherwise never be sent. Calls up to this long are caught. The
/// server de-duplicates (caller + number + exact call time), so sending a call again is harmless.
const Duration kCallSyncReplayWindow = Duration(hours: 3);

/// Most calls sent in one /calls/sync request (the server accepts up to 5000 and 2 MB).
const int kCallSyncBatchSize = 500;

/// Calls in a replay window around the last acknowledgement. Android can
/// expose a call before its final duration/type is written, so replaying recent
/// rows lets the server update the existing deduplicated record.
List<CallLogModel> callsNewerThan(
  List<CallLogModel> calls,
  DateTime? lastAcked, {
  Duration replayWindow = kCallSyncReplayWindow,
}) {
  if (lastAcked == null) return List<CallLogModel>.of(calls);
  final replayFrom = lastAcked.subtract(replayWindow);
  return calls.where((c) => !c.timestamp.isBefore(replayFrom)).toList();
}

/// The server's de-duplication key for a call: exact start time + number.
String callSyncKey(CallLogModel c) => '${c.timestamp.millisecondsSinceEpoch}_${last10Digits(c.phoneNumber)}';

/// The call facts the server updates on a re-send (type, talk time, SIM).
String callSyncSignature(CallLogModel c) => '${c.type.name}_${c.duration.inSeconds}_${c.simSlot}';

/// Calls to send, oldest first: inside the replay window and not already acknowledged by the
/// server with the same facts ([sent]: [callSyncKey] -> [callSyncSignature]). A call whose
/// duration or type changed after it was sent is sent again.
List<CallLogModel> callsToSync(
  List<CallLogModel> calls,
  DateTime? lastAcked,
  Map<String, String> sent, {
  Duration replayWindow = kCallSyncReplayWindow,
}) {
  final list = callsNewerThan(calls, lastAcked, replayWindow: replayWindow)
      .where((c) => sent[callSyncKey(c)] != callSyncSignature(c))
      .toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return list;
}

/// Forgets acknowledged calls that are older than the replay window (they are never re-checked).
void pruneSentCallSignatures(
  Map<String, String> sent,
  DateTime? lastAcked, {
  Duration replayWindow = kCallSyncReplayWindow,
}) {
  if (lastAcked == null) return;
  final cutoff = lastAcked.subtract(replayWindow).millisecondsSinceEpoch;
  sent.removeWhere((key, _) {
    final ms = int.tryParse(key.split('_').first);
    return ms != null && ms < cutoff;
  });
}

DateTime? newestTimestamp(List<CallLogModel> calls) {
  DateTime? best;
  for (final c in calls) {
    if (best == null || c.timestamp.isAfter(best)) best = c.timestamp;
  }
  return best;
}

/// The call-log row a recording belongs to: same customer number (last 10 digits) and a start
/// time within [window] of [startedAt]; the closest one wins. Null when nothing qualifies.
CallLogModel? matchCallForRecording(
  List<CallLogModel> calls, {
  required String phone,
  required DateTime startedAt,
  Duration window = const Duration(minutes: 5),
}) {
  CallLogModel? best;
  int bestDiff = 1 << 62;
  final hasPhone = last10Digits(phone).length == 10;
  for (final c in calls) {
    if (hasPhone && !samePhone(c.phoneNumber, phone)) continue;
    final diff = (c.timestamp.millisecondsSinceEpoch - startedAt.millisecondsSinceEpoch).abs();
    if (diff > window.inMilliseconds) continue;
    if (diff < bestDiff) {
      bestDiff = diff;
      best = c;
    }
  }
  return best;
}

// ---------------------------------------------------------------- Callbacks

/// A callback time must be in the future: anything at or before [now] moves to 10:00 the next day.
DateTime normalizeCallbackTime(DateTime candidate, DateTime now) {
  if (candidate.isAfter(now)) return candidate;
  final tomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10, 0);
}

/// Default follow-up slot: [hoursAhead] from now clamped to working hours (9-18), never in the past.
DateTime defaultCallbackTime(DateTime now, {int hoursAhead = 3}) {
  final hour = (now.hour + hoursAhead).clamp(9, 18);
  return normalizeCallbackTime(DateTime(now.year, now.month, now.day, hour, 0), now);
}

// ---------------------------------------------------------------- Live team board (manager home)

enum TeamLiveState { onCall, available, onBreak, offline }

class TeamLiveMember {
  final String id;
  final String name;
  final TeamLiveState state;
  final String breakType;
  final bool recordingOff;

  const TeamLiveMember({
    required this.id,
    required this.name,
    required this.state,
    this.breakType = '',
    this.recordingOff = false,
  });
}

class TeamLiveBoard {
  final List<TeamLiveMember> members;

  /// Names of members with auto call recording turned off; null when the server did not say.
  final List<String>? recordingOffNames;

  const TeamLiveBoard({required this.members, this.recordingOffNames});

  List<TeamLiveMember> inState(TeamLiveState s) => members.where((m) => m.state == s).toList();
}

/// Live status of the team from GET /dashboard/stats (no extra request):
/// - `callerLiveStatuses`: `status` ON CALL (a call in the last 15 minutes) / ONLINE / OFFLINE;
/// - `teamMembers`: `online`, `onBreak`, `breakType`, `autoRecordEnabled` per member;
/// - `disabledRecorders`: members with auto call recording off.
/// A member on a break counts as on break first, then on call, then available (online), else offline.
/// Null when the response carries neither list.
TeamLiveBoard? teamLiveBoardFromStats(Map<String, dynamic>? stats) {
  if (stats == null) return null;
  final liveRaw = stats['callerLiveStatuses'];
  final membersRaw = stats['teamMembers'];
  if (liveRaw is! List && membersRaw is! List) return null;

  final liveById = <String, String>{};
  final liveRows = <Map<String, dynamic>>[];
  if (liveRaw is List) {
    for (final r in liveRaw.whereType<Map>()) {
      final row = Map<String, dynamic>.from(r);
      liveRows.add(row);
      final id = asString(row['id']);
      if (id.isNotEmpty) liveById[id] = asString(row['status']).toUpperCase();
    }
  }

  final disabledIds = <String>{};
  List<String>? recordingOffNames;
  final disabledRaw = stats['disabledRecorders'];
  if (disabledRaw is List) {
    recordingOffNames = [];
    for (final r in disabledRaw.whereType<Map>()) {
      final id = asString(r['id']);
      if (id.isNotEmpty) disabledIds.add(id);
      final name = asString(r['name'], asString(r['phone']));
      if (name.isNotEmpty) recordingOffNames.add(name);
    }
  }

  final rows = membersRaw is List && membersRaw.isNotEmpty
      ? membersRaw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
      : liveRows;
  final fromMembersFlag = <String>[];
  var anyRecordingFlag = false;
  final members = <TeamLiveMember>[];
  for (final m in rows) {
    final id = asString(m['id']);
    final name = asString(m['name'], asString(m['phone'], '—'));
    final live = liveById[id] ?? asString(m['status']).toUpperCase();
    final onBreak = asBool(m['onBreak']);
    final online = asBool(m['online']) || live == 'ONLINE';
    final TeamLiveState state;
    if (onBreak) {
      state = TeamLiveState.onBreak;
    } else if (live == 'ON CALL') {
      state = TeamLiveState.onCall;
    } else if (online) {
      state = TeamLiveState.available;
    } else {
      state = TeamLiveState.offline;
    }
    var recordingOff = id.isNotEmpty && disabledIds.contains(id);
    if (m.containsKey('autoRecordEnabled')) {
      anyRecordingFlag = true;
      if (!asBool(m['autoRecordEnabled'], true)) {
        recordingOff = true;
        fromMembersFlag.add(name);
      }
    }
    members.add(TeamLiveMember(
      id: id,
      name: name,
      state: state,
      breakType: onBreak ? asString(m['breakType'], 'Break') : '',
      recordingOff: recordingOff,
    ));
  }
  if (recordingOffNames == null && anyRecordingFlag) recordingOffNames = fromMembersFlag;
  return TeamLiveBoard(members: members, recordingOffNames: recordingOffNames);
}

/// The team's daily call target (`teamDailyTarget`: sum of the agents' (callers') targets in the
/// selected scope) and the calls counted for the selected period (`totalCalls`). Null when the server
/// did not send a target.
({int target, int calls})? teamTargetFromStats(Map<String, dynamic>? stats) {
  if (stats == null || !stats.containsKey('teamDailyTarget')) return null;
  final target = asInt(stats['teamDailyTarget'], -1);
  if (target <= 0) return null;
  return (target: target, calls: asInt(stats['totalCalls']));
}
