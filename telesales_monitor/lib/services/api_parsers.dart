// Pure JSON / domain helpers shared by ApiService and TeleProvider.
// No Flutter bindings, no I/O: everything here is covered by unit tests in test/.

import '../models/call_log_model.dart';
import '../models/employee_model.dart';
import '../models/lead_model.dart';
import '../models/recording_model.dart';

/// JSON numbers may arrive as int, double or numeric strings. Never throws.
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
    dailyTarget: asInt(e['dailyTarget'], 40) > 0 ? asInt(e['dailyTarget'], 40) : 40,
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

/// Calls in a small replay window around the last acknowledgement. Android can
/// expose a call before its final duration/type is written, so replaying recent
/// rows lets the server update the existing deduplicated record.
List<CallLogModel> callsNewerThan(List<CallLogModel> calls, DateTime? lastAcked) {
  if (lastAcked == null) return List<CallLogModel>.of(calls);
  final replayFrom = lastAcked.subtract(const Duration(minutes: 10));
  return calls.where((c) => !c.timestamp.isBefore(replayFrom)).toList();
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
