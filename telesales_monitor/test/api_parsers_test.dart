import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telesales_monitor/models/call_log_model.dart';
import 'package:telesales_monitor/models/lead_model.dart';
import 'package:telesales_monitor/services/api_parsers.dart';
import 'package:telesales_monitor/services/api_service.dart';

CallLogModel call(
  String id,
  String phone,
  DateTime at, {
  CallType type = CallType.outgoing,
  int slot = 1,
}) => CallLogModel(
  id: id,
  contactName: 'C$id',
  phoneNumber: phone,
  type: type,
  duration: const Duration(seconds: 30),
  timestamp: at,
  simSlot: slot,
);

void main() {
  group('asInt', () {
    test('accepts int, double, numeric string; never throws', () {
      expect(asInt(5), 5);
      expect(asInt(5.9), 5);
      expect(asInt('12'), 12);
      expect(asInt('12.7'), 12);
      expect(asInt(null), 0);
      expect(asInt('abc', 7), 7);
      expect(asInt(true), 0);
    });
  });

  group('phone matching', () {
    test('last10Digits strips formatting and country code', () {
      expect(last10Digits('+91 98250 12340'), '9825012340');
      expect(last10Digits('09825012340'), '9825012340');
      expect(last10Digits(''), '');
      expect(last10Digits(null), '');
    });

    test('samePhone requires an exact 10-digit tail match', () {
      expect(samePhone('+919825012340', '9825012340'), isTrue);
      expect(samePhone('9825012340', '9825012341'), isFalse);
      // Empty / short numbers never match (old bug: endsWith('') was always true)
      expect(samePhone('', '9825012340'), isFalse);
      expect(samePhone('9825012340', ''), isFalse);
      expect(samePhone('', ''), isFalse);
      expect(samePhone('12340', '9825012340'), isFalse);
    });
  });

  group('lead status wire mapping', () {
    test('newLead <-> new', () {
      expect(leadStatusToWire(LeadStatus.newLead), 'new');
      expect(leadStatusFromWire('new'), LeadStatus.newLead);
    });

    test('every enum value round-trips by name', () {
      for (final s in LeadStatus.values) {
        expect(leadStatusFromWire(leadStatusToWire(s)), s, reason: s.name);
      }
    });

    test('statuses the old if-chain dropped are kept', () {
      expect(leadStatusFromWire('bookDemo'), LeadStatus.bookDemo);
      expect(leadStatusFromWire('demoDone'), LeadStatus.demoDone);
      expect(leadStatusFromWire('notInterested'), LeadStatus.notInterested);
      expect(leadStatusFromWire('warned'), LeadStatus.warned);
    });

    test('unknown / empty fall back, case-insensitive names accepted', () {
      expect(leadStatusFromWire(null), LeadStatus.newLead);
      expect(leadStatusFromWire('somethingElse'), LeadStatus.newLead);
      expect(leadStatusFromWire('FOLLOWUP'), LeadStatus.followUp);
    });
  });

  group('JSON parsing', () {
    test('leadFromJson reads server dates, ids and assignment', () {
      final lead = leadFromJson({
        'id': 'L1',
        'name': 'Acme',
        'phone': '9825012340',
        'status': 'bookDemo',
        'attempts': 3.0,
        'assignedCallerId': 'U7',
        'assignedCaller': 'Asha',
        'notes': 'call after 5',
        'lastCallDate': '2026-09-01T10:00:00.000Z',
        'createdAt': '2026-08-01T10:00:00.000Z',
      });
      expect(lead.id, 'L1');
      expect(lead.status, LeadStatus.bookDemo);
      expect(lead.attempts, 3);
      expect(lead.assignedCallerId, 'U7');
      expect(lead.assignedTo, 'Asha');
      expect(lead.note, 'call after 5');
      expect(lead.lastCallDate.toUtc(), DateTime.utc(2026, 9, 1, 10));
      expect(lead.dateAdded.toUtc(), DateTime.utc(2026, 8, 1, 10));
    });

    test('employeeFromJson uses real split counts and managerId', () {
      final e = employeeFromJson({
        'id': 'U1',
        'name': 'Asha',
        'role': 'caller',
        'managerId': 'M9',
        'totalCalls': 40,
        'connectedCalls': 30.0,
        'incomingCalls': 7,
        'outgoingCalls': 33,
        'missedCalls': 2,
        'neverAttendedCalls': 4,
        'talkTimeSeconds': 3600.4,
        'rank': 2,
        'dailyTarget': 55,
      });
      expect(e.reportingManagerId, 'M9');
      expect(e.incomingCalls, 7);
      expect(e.outgoingCalls, 33);
      expect(e.missedCalls, 2);
      expect(e.neverAttendedCalls, 4);
      expect(e.connectedCalls, 30);
      expect(e.totalTalkTime, const Duration(hours: 1));
      expect(e.dailyTarget, 55);
    });

    test('employeeFromJson tolerates missing fields', () {
      final e = employeeFromJson({'id': 'U2', 'name': 'X'});
      expect(e.totalCalls, 0);
      expect(e.reportingManagerId, isNull);
      expect(e.dailyTarget, kDefaultDailyTarget);
    });

    test(
      'recordingFromJson builds an absolute audio url and prefers callStartedAt',
      () {
        final r = recordingFromJson({
          'id': 'R1',
          'callerName': 'Asha',
          'phoneNumber': '9825012340',
          'durationSeconds': 65.0,
          'audioUrl': '/api/recordings/R1/audio',
          'fileName': 'OUT_CALL_REC_1.wav',
          'callStartedAt': '2026-09-01T10:00:00.000Z',
          'createdAt': '2026-09-01T10:05:00.000Z',
          'rating': 4.5,
        }, 'https://telesales.askeva.io/api');
        expect(
          r.audioUrl,
          'https://telesales.askeva.io/api/recordings/R1/audio',
        );
        expect(r.duration, const Duration(seconds: 65));
        expect(r.date.toUtc(), DateTime.utc(2026, 9, 1, 10));
        expect(r.rating, 4);
        expect(r.fileName, 'OUT_CALL_REC_1.wav');
      },
    );

    test('recordingFromJson accepts true-like values for pinned', () {
      expect(recordingFromJson({'pinned': 1}, 'https://example.com').pinned, isTrue);
      expect(recordingFromJson({'pinned': 'true'}, 'https://example.com').pinned, isTrue);
      expect(recordingFromJson({'pinned': '0'}, 'https://example.com').pinned, isFalse);
    });

    test('withTokenQuery appends the token once', () {
      expect(
        withTokenQuery('https://h/api/recordings/1/audio', 'abc'),
        'https://h/api/recordings/1/audio?token=abc',
      );
      expect(
        withTokenQuery('https://h/a?x=1', 'abc'),
        'https://h/a?x=1&token=abc',
      );
      expect(
        withTokenQuery('https://h/a?token=zzz', 'abc'),
        'https://h/a?token=zzz',
      );
      expect(withTokenQuery('https://h/a', ''), 'https://h/a');
    });
  });

  group('call sync', () {
    final t0 = DateTime(2026, 9, 18, 10);
    final calls = [
      call('1', '9825012340', t0),
      call('2', '9825012341', t0.add(const Duration(minutes: 10))),
      call('3', '9825012342', t0.add(const Duration(minutes: 20))),
    ];

    test('replays recent calls so late device updates reach the server', () {
      expect(callsNewerThan(calls, null).length, 3);
      expect(
        callsNewerThan(
          calls,
          t0.add(const Duration(minutes: 10)),
        ).map((c) => c.id),
        ['1', '2', '3'],
      );
      // Replay window is 3 hours
      expect(callsNewerThan(calls, t0.add(const Duration(hours: 1))).length, 3);
      expect(callsNewerThan(calls, t0.add(const Duration(hours: 4))), isEmpty);
      expect(
        callsNewerThan(calls, t0.add(const Duration(hours: 1)), replayWindow: const Duration(minutes: 10)),
        isEmpty,
      );
    });

    test('a long call logged after a later call is still sent', () {
      // 40-minute call started at 10:00, written to the log at 10:40; a short call at 10:30
      // was already acknowledged
      final long = call('long', '9825012349', t0);
      final shortAck = t0.add(const Duration(minutes: 30));
      final sent = {callSyncKey(call('s', '9825012348', shortAck)): callSyncSignature(call('s', '9825012348', shortAck))};
      final list = [call('s', '9825012348', shortAck), long];
      expect(callsToSync(list, shortAck, sent).map((c) => c.id), ['long']);
    });

    test('callsToSync skips calls the server has with the same facts, oldest first', () {
      final sent = <String, String>{};
      expect(callsToSync(calls, null, sent).map((c) => c.id), ['1', '2', '3']);
      for (final c in calls) {
        sent[callSyncKey(c)] = callSyncSignature(c);
      }
      expect(callsToSync(calls, t0.add(const Duration(minutes: 20)), sent), isEmpty);
      // The device finished writing call 3 (longer talk time): it is sent again
      final updated = CallLogModel(
        id: '3',
        contactName: 'C3',
        phoneNumber: '9825012342',
        type: CallType.outgoing,
        duration: const Duration(seconds: 95),
        timestamp: t0.add(const Duration(minutes: 20)),
        simSlot: 1,
      );
      expect(
        callsToSync([calls[0], calls[1], updated], t0.add(const Duration(minutes: 20)), sent).map((c) => c.id),
        ['3'],
      );
      // Unordered input comes back oldest first
      expect(callsToSync(calls.reversed.toList(), null, {}).map((c) => c.id), ['1', '2', '3']);
    });

    test('pruneSentCallSignatures forgets calls older than the window', () {
      final old = call('o', '9825012340', t0.subtract(const Duration(hours: 5)));
      final sent = {
        callSyncKey(old): callSyncSignature(old),
        callSyncKey(calls[0]): callSyncSignature(calls[0]),
      };
      pruneSentCallSignatures(sent, t0);
      expect(sent.keys, [callSyncKey(calls[0])]);
      pruneSentCallSignatures(sent, null); // nothing acknowledged yet: unchanged
      expect(sent.length, 1);
    });

    test('newestTimestamp', () {
      expect(newestTimestamp(calls), t0.add(const Duration(minutes: 20)));
      expect(newestTimestamp([]), isNull);
    });
  });

  group('recording to call matching', () {
    final t0 = DateTime(2026, 9, 18, 10);
    final calls = [
      call('a', '9825012340', t0),
      call('b', '9825012340', t0.add(const Duration(minutes: 3))),
      call('c', '9000000000', t0.add(const Duration(minutes: 1))),
    ];

    test('same number, closest start time wins', () {
      final m = matchCallForRecording(
        calls,
        phone: '+91 98250 12340',
        startedAt: t0.add(const Duration(minutes: 2, seconds: 50)),
      );
      expect(m?.id, 'b');
    });

    test('never attaches to a different customer number', () {
      final m = matchCallForRecording(
        calls,
        phone: '9111111111',
        startedAt: t0,
      );
      expect(m, isNull);
    });

    test('outside the 5 minute window there is no match', () {
      final m = matchCallForRecording(
        calls,
        phone: '9825012340',
        startedAt: t0.add(const Duration(minutes: 30)),
      );
      expect(m, isNull);
    });

    test('unknown number falls back to the closest call in time', () {
      final m = matchCallForRecording(
        calls,
        phone: '',
        startedAt: t0.add(const Duration(seconds: 50)),
      );
      expect(m?.id, 'c');
    });
  });

  group('callback times', () {
    final now = DateTime(2026, 9, 18, 15, 30);

    test('future times are kept', () {
      final t = DateTime(2026, 9, 18, 16);
      expect(normalizeCallbackTime(t, now), t);
    });

    test('past or current times move to 10:00 next day', () {
      expect(
        normalizeCallbackTime(DateTime(2026, 9, 18, 9), now),
        DateTime(2026, 9, 19, 10),
      );
      expect(normalizeCallbackTime(now, now), DateTime(2026, 9, 19, 10));
    });

    test('month rollover', () {
      expect(
        normalizeCallbackTime(
          DateTime(2026, 9, 30, 8),
          DateTime(2026, 9, 30, 20),
        ),
        DateTime(2026, 10, 1, 10),
      );
    });

    test('default callback is never in the past', () {
      expect(
        defaultCallbackTime(DateTime(2026, 9, 18, 10)),
        DateTime(2026, 9, 18, 13),
      );
      // 17:00 + 3h clamps to 18:00 today (still in the future)
      expect(
        defaultCallbackTime(DateTime(2026, 9, 18, 17)),
        DateTime(2026, 9, 18, 18),
      );
      // 20:00: 18:00 today already passed -> tomorrow 10:00
      expect(
        defaultCallbackTime(DateTime(2026, 9, 18, 20)),
        DateTime(2026, 9, 19, 10),
      );
      // Early morning: clamps up to 9:00 today
      expect(
        defaultCallbackTime(DateTime(2026, 9, 18, 2)),
        DateTime(2026, 9, 18, 9),
      );
    });
  });

  group('host failover', () {
    test(
      'only pre-send connection failures may be retried on another host',
      () {
        expect(
          ApiService.isConnectionError(
            const SocketException('Failed host lookup: telesales.askeva.io'),
          ),
          isTrue,
        );
        expect(
          ApiService.isConnectionError(
            const SocketException('Connection refused'),
          ),
          isTrue,
        );
        expect(
          ApiService.isConnectionError(
            http.ClientException('Connection refused'),
          ),
          isTrue,
        );
        expect(
          ApiService.isConnectionError(
            const SocketException('Connection reset by peer'),
          ),
          isFalse,
        );
        expect(
          ApiService.isConnectionError(
            http.ClientException('Connection closed while receiving data'),
          ),
          isFalse,
        );
        expect(ApiService.isConnectionError(Exception('timeout')), isFalse);
      },
    );

    test('production host is HTTPS with no local fallback', () {
      expect(ApiService.productionBaseUrl, startsWith('https://'));
      expect(ApiService.candidateBaseUrlsFor(ApiService.productionBaseUrl), [
        ApiService.productionBaseUrl,
      ]);
    });

    test('local debug default tries USB (adb reverse) before the emulator host', () {
      expect(ApiService.candidateBaseUrlsFor(ApiService.debugUsbBaseUrl), [
        'http://127.0.0.1:5000/api',
        'http://10.0.2.2:5000/api',
      ]);
    });

    test('starts from the configured API URL', () {
      expect(ApiService.preferredBaseUrl, ApiService.configuredBaseUrl);
      expect(ApiService.candidateBaseUrls.first, ApiService.configuredBaseUrl);
    });

    test('a build without API_URL uses the live server, also in debug', () {
      // flutter test runs in debug mode without --dart-define: a plain `flutter run` behaves the same
      expect(ApiService.configuredBaseUrl, ApiService.productionBaseUrl);
    });

    test('USB URL help explains the run_on_phone script', () {
      final help = ApiService.simConnectionHelpFor(ApiService.debugUsbBaseUrl);
      expect(help, contains('run_on_phone.ps1'));
      expect(help, contains('adb reverse'));
    });

    test('custom API URLs do not fall back to another database', () {
      expect(ApiService.candidateBaseUrlsFor('http://192.168.1.18:5000/api'), [
        'http://192.168.1.18:5000/api',
      ]);
    });

    test('local connection help points to the configured backend', () {
      final help = ApiService.simConnectionHelpFor(
        'http://192.168.1.18:5000/api',
      );
      expect(help, contains('http://192.168.1.18:5000/api/health'));
      expect(help, contains('Windows Firewall'));
      expect(help, isNot(contains('10.0.2.2')));
    });

    test('emulator URL is identified as unsuitable for physical phones', () {
      final help = ApiService.simConnectionHelpFor(
        ApiService.debugEmulatorBaseUrl,
      );
      expect(help, contains('Android emulator'));
      expect(help, contains('physical phone'));
    });
  });

  group('live team board', () {
    test('combines live status, breaks and recording off from /dashboard/stats', () {
      final board = teamLiveBoardFromStats({
        'callerLiveStatuses': [
          {'id': 'a', 'name': 'Asha', 'status': 'ON CALL'},
          {'id': 'b', 'name': 'Bala', 'status': 'ONLINE'},
          {'id': 'c', 'name': 'Chitra', 'status': 'OFFLINE'},
          {'id': 'd', 'name': 'Dev', 'status': 'ONLINE'},
        ],
        'teamMembers': [
          {'id': 'a', 'name': 'Asha', 'online': true, 'onBreak': false, 'autoRecordEnabled': true},
          {'id': 'b', 'name': 'Bala', 'online': true, 'onBreak': false, 'autoRecordEnabled': false},
          {'id': 'c', 'name': 'Chitra', 'online': false, 'onBreak': false, 'autoRecordEnabled': true},
          {'id': 'd', 'name': 'Dev', 'online': true, 'onBreak': true, 'breakType': 'Lunch', 'autoRecordEnabled': true},
        ],
        'disabledRecorders': [
          {'id': 'b', 'name': 'Bala', 'phone': '9825012340'},
        ],
      })!;
      expect(board.members.length, 4);
      expect(board.inState(TeamLiveState.onCall).map((m) => m.name), ['Asha']);
      expect(board.inState(TeamLiveState.available).map((m) => m.name), ['Bala']);
      expect(board.inState(TeamLiveState.offline).map((m) => m.name), ['Chitra']);
      final onBreak = board.inState(TeamLiveState.onBreak);
      expect(onBreak.map((m) => m.name), ['Dev']);
      expect(onBreak.single.breakType, 'Lunch');
      expect(board.recordingOffNames, ['Bala']);
    });

    test('works with only callerLiveStatuses; null without any list', () {
      final board = teamLiveBoardFromStats({
        'callerLiveStatuses': [
          {'id': 'a', 'name': 'Asha', 'status': 'ONLINE'},
        ],
      })!;
      expect(board.inState(TeamLiveState.available).length, 1);
      expect(board.recordingOffNames, isNull); // the server did not say
      expect(teamLiveBoardFromStats({'totalCalls': 3}), isNull);
      expect(teamLiveBoardFromStats(null), isNull);
    });

    test('team target needs a positive teamDailyTarget', () {
      expect(teamTargetFromStats({'teamDailyTarget': 500, 'totalCalls': 120}), (target: 500, calls: 120));
      expect(teamTargetFromStats({'teamDailyTarget': 0, 'totalCalls': 1}), isNull);
      expect(teamTargetFromStats({'totalCalls': 1}), isNull);
      expect(teamTargetFromStats(null), isNull);
    });
  });
}
