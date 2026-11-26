// Outbox for changes an agent saved while the server could not take them (offline / 5xx):
// lead status / note / call outcome updates (one entry per lead) and contact saves (one entry per
// number). Stored in SharedPreferences per user and sent again later. Pure model, no I/O.

import 'dart:convert';

import '../models/lead_model.dart';
import 'api_parsers.dart';

/// What happened to a change the agent saved. Ordered from best to worst (see [combineSaveResults]).
enum LeadSaveResult {
  /// The server has it.
  saved,

  /// Saved on this phone only: the lead is a local call-log contact, not a CRM lead.
  localOnly,

  /// Saved on this phone; sent automatically when the server can be reached.
  queued,

  /// Saved on this phone, but the server refused it (4xx): it will not be sent again.
  rejected,
}

/// The worse of two results (e.g. status saved + note queued = queued).
LeadSaveResult combineSaveResults(LeadSaveResult a, LeadSaveResult b) => a.index >= b.index ? a : b;

/// Message for a snack bar. [saved] is the screen's own success text.
String leadSaveMessage(LeadSaveResult r, {String saved = 'Saved'}) => switch (r) {
      LeadSaveResult.saved => saved,
      LeadSaveResult.localOnly => '$saved (on this phone)',
      LeadSaveResult.queued => 'Saved on this phone – will sync when online',
      LeadSaveResult.rejected => 'Saved on this phone only – the server did not accept it',
    };

/// Entries not sent within this time are dropped.
const Duration kOutboxMaxAge = Duration(days: 7);

/// SharedPreferences key of [userId]'s outbox (kept across logout, replayed at the next login).
String outboxPrefsKey(String userId) => 'lead_outbox_v1_$userId';

class OutboxEntry {
  static const String typeLead = 'lead';
  static const String typeContact = 'contact';

  final String type;

  /// Lead update: the server lead id. Contact save: unused ('').
  final String leadId;
  final String phone;

  /// Lead update: [LeadStatus.name] to set, null = unchanged.
  final String? status;

  /// Lead update: notes to set, null = unchanged. Contact save: the notes sent with it.
  final String? notes;

  /// Lead update: count one call attempt.
  final bool logAttempt;

  /// Contact save: the contact name.
  final String name;

  /// When this entry last changed (the 7-day expiry counts from here).
  final int updatedAtMs;

  const OutboxEntry({
    required this.type,
    this.leadId = '',
    required this.phone,
    this.status,
    this.notes,
    this.logAttempt = false,
    this.name = '',
    required this.updatedAtMs,
  });

  factory OutboxEntry.leadUpdate({
    required String leadId,
    required String phone,
    String? status,
    String? notes,
    bool logAttempt = false,
    DateTime? now,
  }) =>
      OutboxEntry(
        type: typeLead,
        leadId: leadId,
        phone: phone,
        status: status,
        notes: notes,
        logAttempt: logAttempt,
        updatedAtMs: (now ?? DateTime.now()).millisecondsSinceEpoch,
      );

  factory OutboxEntry.contactSave({
    required String phone,
    required String name,
    String? notes,
    DateTime? now,
  }) =>
      OutboxEntry(
        type: typeContact,
        phone: phone,
        name: name,
        notes: notes,
        updatedAtMs: (now ?? DateTime.now()).millisecondsSinceEpoch,
      );

  /// One entry per lead (lead id) / per number (contact saves).
  String get key => type == typeContact ? 'contact:${last10Digits(phone)}' : leadId;

  LeadStatus? get leadStatus {
    final s = status;
    if (s == null) return null;
    for (final v in LeadStatus.values) {
      if (v.name == s) return v;
    }
    return null;
  }

  /// [newer] applied on top of this entry: the latest value of each field wins; an attempt that
  /// is still waiting is kept.
  OutboxEntry mergedWith(OutboxEntry newer) => OutboxEntry(
        type: newer.type,
        leadId: newer.leadId.isNotEmpty ? newer.leadId : leadId,
        phone: newer.phone.isNotEmpty ? newer.phone : phone,
        status: newer.status ?? status,
        notes: newer.notes ?? notes,
        logAttempt: logAttempt || newer.logAttempt,
        name: newer.name.isNotEmpty ? newer.name : name,
        updatedAtMs: newer.updatedAtMs > updatedAtMs ? newer.updatedAtMs : updatedAtMs,
      );

  /// Same entry without the call attempt (a timed-out request may already have counted it).
  OutboxEntry withoutAttempt() => OutboxEntry(
        type: type,
        leadId: leadId,
        phone: phone,
        status: status,
        notes: notes,
        logAttempt: false,
        name: name,
        updatedAtMs: updatedAtMs,
      );

  bool isExpired(DateTime now) =>
      now.millisecondsSinceEpoch - updatedAtMs > kOutboxMaxAge.inMilliseconds;

  Map<String, dynamic> toJson() => {
        'type': type,
        if (leadId.isNotEmpty) 'leadId': leadId,
        'phone': phone,
        'status': ?status,
        'notes': ?notes,
        if (logAttempt) 'logAttempt': true,
        if (name.isNotEmpty) 'name': name,
        'updatedAtMs': updatedAtMs,
      };

  /// Null for a malformed entry.
  static OutboxEntry? fromJson(Map<String, dynamic> m) {
    final type = asString(m['type']);
    if (type != typeLead && type != typeContact) return null;
    final entry = OutboxEntry(
      type: type,
      leadId: asString(m['leadId']),
      phone: asString(m['phone']),
      status: m['status']?.toString(),
      notes: m['notes']?.toString(),
      logAttempt: asBool(m['logAttempt']),
      name: asString(m['name']),
      updatedAtMs: asInt(m['updatedAtMs']),
    );
    if (type == typeLead && entry.leadId.isEmpty) return null;
    if (type == typeContact && (last10Digits(entry.phone).isEmpty || entry.name.isEmpty)) return null;
    return entry;
  }
}

/// Stored outbox -> entries by [OutboxEntry.key], without expired or malformed ones. Never throws.
Map<String, OutboxEntry> decodeOutbox(String? json, {required DateTime now}) {
  final result = <String, OutboxEntry>{};
  if (json == null || json.isEmpty) return result;
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return result;
    for (final item in decoded) {
      if (item is! Map) continue;
      final entry = OutboxEntry.fromJson(Map<String, dynamic>.from(item));
      if (entry == null || entry.isExpired(now)) continue;
      final existing = result[entry.key];
      result[entry.key] = existing == null ? entry : existing.mergedWith(entry);
    }
  } catch (_) {}
  return result;
}

String encodeOutbox(Map<String, OutboxEntry> entries) =>
    jsonEncode(entries.values.map((e) => e.toJson()).toList());
