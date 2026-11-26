import 'package:flutter_test/flutter_test.dart';
import 'package:telesales_monitor/models/lead_model.dart';
import 'package:telesales_monitor/services/api_service.dart';
import 'package:telesales_monitor/services/lead_outbox.dart';

void main() {
  final now = DateTime(2026, 11, 24, 12);

  group('OutboxEntry', () {
    test('one entry per lead: the latest value of each field wins, a waiting attempt is kept', () {
      final first = OutboxEntry.leadUpdate(
        leadId: 'L1',
        phone: '9825012340',
        status: LeadStatus.followUp.name,
        notes: 'call after lunch',
        logAttempt: true,
        now: now,
      );
      final second = OutboxEntry.leadUpdate(
        leadId: 'L1',
        phone: '9825012340',
        status: LeadStatus.interested.name,
        now: now.add(const Duration(minutes: 5)),
      );
      final merged = first.mergedWith(second);
      expect(merged.key, 'L1');
      expect(merged.leadStatus, LeadStatus.interested);
      expect(merged.notes, 'call after lunch'); // second did not change the note
      expect(merged.logAttempt, isTrue);
      expect(merged.updatedAtMs, now.add(const Duration(minutes: 5)).millisecondsSinceEpoch);
      expect(merged.withoutAttempt().logAttempt, isFalse);
    });

    test('contact saves are keyed by number', () {
      final a = OutboxEntry.contactSave(phone: '+91 98250 12340', name: 'Ravi', now: now);
      final b = OutboxEntry.contactSave(phone: '9825012340', name: 'Ravi K', now: now);
      expect(a.key, b.key);
      expect(a.mergedWith(b).name, 'Ravi K');
    });

    test('encode / decode round trip drops expired and malformed entries', () {
      final fresh = OutboxEntry.leadUpdate(leadId: 'L1', phone: '9825012340', status: 'won', now: now);
      final old = OutboxEntry.leadUpdate(
        leadId: 'L2',
        phone: '9825012341',
        status: 'lost',
        now: now.subtract(const Duration(days: 8)),
      );
      final contact = OutboxEntry.contactSave(phone: '9825012342', name: 'Meena', notes: 'demo', now: now);
      final json = encodeOutbox({fresh.key: fresh, old.key: old, contact.key: contact});
      final decoded = decodeOutbox(json, now: now);
      expect(decoded.keys.toSet(), {'L1', contact.key});
      expect(decoded['L1']!.leadStatus, LeadStatus.won);
      expect(decoded[contact.key]!.notes, 'demo');

      expect(decodeOutbox('not json', now: now), isEmpty);
      expect(decodeOutbox('[{"type":"lead","phone":"1"}]', now: now), isEmpty); // no lead id
      expect(decodeOutbox(null, now: now), isEmpty);
    });

    test('prefs key is per user', () {
      expect(outboxPrefsKey('u1'), isNot(outboxPrefsKey('u2')));
    });
  });

  group('save results', () {
    test('only no response and 5xx are worth retrying', () {
      expect(const ApiWriteResult(0).retryable, isTrue);
      expect(const ApiWriteResult(503).retryable, isTrue);
      expect(const ApiWriteResult(500).retryable, isTrue);
      expect(const ApiWriteResult(400).retryable, isFalse);
      expect(const ApiWriteResult(403).retryable, isFalse);
      expect(const ApiWriteResult(404).retryable, isFalse);
      expect(const ApiWriteResult(200).ok, isTrue);
      expect(const ApiWriteResult(200).retryable, isFalse);
    });

    test('combined result is the worse one; messages tell saved from waiting', () {
      expect(combineSaveResults(LeadSaveResult.saved, LeadSaveResult.queued), LeadSaveResult.queued);
      expect(combineSaveResults(LeadSaveResult.rejected, LeadSaveResult.saved), LeadSaveResult.rejected);
      expect(combineSaveResults(LeadSaveResult.saved, LeadSaveResult.saved), LeadSaveResult.saved);
      expect(leadSaveMessage(LeadSaveResult.saved, saved: 'Saved'), 'Saved');
      expect(leadSaveMessage(LeadSaveResult.queued), contains('will sync when online'));
      expect(leadSaveMessage(LeadSaveResult.rejected), contains('did not accept'));
    });
  });
}
