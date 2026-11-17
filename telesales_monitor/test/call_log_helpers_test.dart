import 'package:flutter_test/flutter_test.dart';
import 'package:telesales_monitor/models/call_log_model.dart';
import 'package:telesales_monitor/services/call_log_helpers.dart';

CallLogModel call(
  CallType type, {
  int seconds = 0,
  DateTime? at,
  String phone = '9876543210',
}) => CallLogModel(
  id: '${at?.millisecondsSinceEpoch ?? 0}${type.name}$seconds',
  contactName: 'Ravi',
  phoneNumber: phone,
  type: type,
  duration: Duration(seconds: seconds),
  timestamp: at ?? DateTime(2026, 11, 17, 10),
  simSlot: 2,
);

void main() {
  group('call outcome', () {
    test('talk time for a connected call', () {
      expect(callOutcome(call(CallType.outgoing, seconds: 72)), '1m 12s');
      expect(callOutcome(call(CallType.incoming, seconds: 9)), '9s');
    });

    test('says why there was no conversation', () {
      expect(callOutcome(call(CallType.outgoing)), 'Not connected');
      expect(callOutcome(call(CallType.missed)), 'Missed');
      expect(callOutcome(call(CallType.incoming)), 'Missed');
      expect(callOutcome(call(CallType.rejected)), 'Rejected');
      expect(callOutcome(call(CallType.neverAttended)), 'Not answered');
      expect(callHadNoTalk(call(CallType.outgoing)), isTrue);
      expect(callHadNoTalk(call(CallType.outgoing, seconds: 30)), isFalse);
    });
  });

  test('direction label, like the phone\'s call log', () {
    expect(callTypeText(call(CallType.outgoing, seconds: 43)), 'Outgoing');
    expect(callTypeText(call(CallType.outgoing)), 'Outgoing'); // not connected
    expect(callTypeText(call(CallType.incoming, seconds: 20)), 'Incoming');
    expect(callTypeText(call(CallType.incoming)), 'Missed');
    expect(callTypeText(call(CallType.missed)), 'Missed');
    expect(callTypeText(call(CallType.neverAttended)), 'Missed');
    expect(callTypeText(call(CallType.rejected)), 'Rejected');
  });

  group('filters', () {
    final calls = [
      call(CallType.outgoing, seconds: 40),
      call(CallType.outgoing), // not connected: still an outgoing call
      call(CallType.incoming, seconds: 20),
      call(CallType.incoming), // unanswered: missed, not incoming
      call(CallType.missed),
      call(CallType.rejected),
    ];
    int count(CallLogFilter f) =>
        calls.where((c) => matchesCallFilter(c, f)).length;

    test('every call is in ALL, and in exactly one of the others', () {
      expect(count(CallLogFilter.all), calls.length);
      expect(count(CallLogFilter.outgoing), 2);
      expect(count(CallLogFilter.incoming), 1);
      expect(count(CallLogFilter.missed), 3);
      expect(
        count(CallLogFilter.outgoing) +
            count(CallLogFilter.incoming) +
            count(CallLogFilter.missed),
        calls.length,
      );
    });
  });

  group('days', () {
    final now = DateTime(2026, 11, 17, 16, 30);

    test('labels', () {
      expect(callDayLabel(DateTime(2026, 11, 17, 0, 5), now), 'TODAY');
      expect(callDayLabel(DateTime(2026, 11, 16, 23, 59), now), 'YESTERDAY');
      expect(callDayLabel(DateTime(2026, 11, 14, 13, 51), now), '14 NOV');
      expect(callDayLabel(DateTime(2025, 12, 31, 9), now), '31 DEC 2025');
    });

    test(
      'groups newest first, one group per day, calls newest first inside',
      () {
        final groups = groupCallsByDay([
          call(CallType.outgoing, at: DateTime(2026, 11, 14, 13, 8)),
          call(CallType.outgoing, at: DateTime(2026, 11, 17, 9, 7)),
          call(CallType.outgoing, at: DateTime(2026, 11, 14, 13, 51)),
          call(CallType.incoming, at: DateTime(2026, 11, 17, 11)),
        ], now);
        expect(groups.map((g) => g.$1), ['TODAY', '14 NOV']);
        expect(groups[0].$2.map((c) => c.timestamp.hour), [11, 9]);
        expect(groups[1].$2.map((c) => c.timestamp.minute), [51, 8]);
        expect(groupCallsByDay([], now), isEmpty);
      },
    );
  });

  test(
    'calls waiting to sync are the ones newer than the last acknowledged call',
    () {
      final acked = DateTime(2026, 11, 14, 13, 51, 39);
      final calls = [
        call(CallType.outgoing, at: acked), // the acknowledged call itself
        call(CallType.outgoing, at: DateTime(2026, 11, 14, 13, 8)),
        call(CallType.incoming, at: DateTime(2026, 11, 17, 9, 7)),
      ];
      expect(countNotSynced(calls, acked), 1);
      expect(countNotSynced(calls, null), 3); // nothing synced yet
      expect(countNotSynced([], acked), 0);
    },
  );
}
