import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telesales_monitor/services/dialer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DialerService & CallEvent Unit Tests', () {
    const MethodChannel dialerChannel = MethodChannel('com.askeva.telesales/dialer');
    final List<MethodCall> log = <MethodCall>[];

    setUp(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(dialerChannel, (MethodCall methodCall) async {
        log.add(methodCall);
        switch (methodCall.method) {
          case 'getDialerStatus':
            return <dynamic, dynamic>{
              'isDefault': false,
              'isRoleAvailable': true,
            };
          case 'requestDefaultDialerRole':
            return true;
          case 'answerCall':
            return true;
          case 'rejectCall':
            return true;
          case 'endCall':
            return true;
          case 'setMuted':
            return true;
          case 'setSpeaker':
            return true;
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(dialerChannel, null);
    });

    test('DialerStatus parses map correctly', () {
      final status = DialerStatus.fromMap({
        'isDefault': true,
        'isRoleAvailable': true,
      });
      expect(status.isDefault, isTrue);
      expect(status.isRoleAvailable, isTrue);

      final emptyStatus = DialerStatus.fromMap(null);
      expect(emptyStatus.isDefault, isFalse);
      expect(emptyStatus.isRoleAvailable, isFalse);
    });

    test('CallEvent parses states correctly', () {
      final ringing = CallEvent.fromMap({
        'event': 'callStateChanged',
        'state': 'RINGING',
        'phoneNumber': '+919876543210',
        'displayName': 'Test Caller',
        'isIncoming': true,
        'timestamp': 1700000000000,
      });
      expect(ringing.state, equals(CallState.ringing));
      expect(ringing.phoneNumber, equals('+919876543210'));
      expect(ringing.displayName, equals('Test Caller'));
      expect(ringing.isIncoming, isTrue);

      final active = CallEvent.fromMap({
        'event': 'callStateChanged',
        'state': 'ACTIVE',
      });
      expect(active.state, equals(CallState.active));

      final disconnected = CallEvent.fromMap({
        'event': 'callStateChanged',
        'state': 'DISCONNECTED',
      });
      expect(disconnected.state, equals(CallState.disconnected));

      final unknown = CallEvent.fromMap({
        'event': 'callStateChanged',
        'state': 'SOMETHING_ELSE',
      });
      expect(unknown.state, equals(CallState.none));
    });

    test('getDialerStatus invokes native method and returns status', () async {
      final service = DialerService(methodChannel: dialerChannel);
      final status = await service.getDialerStatus();

      expect(log, hasLength(1));
      expect(log.first.method, equals('getDialerStatus'));
      expect(status.isDefault, isFalse);
      expect(status.isRoleAvailable, isTrue);
    });

    test('requestDefaultDialerRole invokes native method', () async {
      final service = DialerService(methodChannel: dialerChannel);
      final res = await service.requestDefaultDialerRole();

      expect(log, hasLength(1));
      expect(log.first.method, equals('requestDefaultDialerRole'));
      expect(res, isTrue);
    });

    test('call actions invoke proper native methods', () async {
      final service = DialerService(methodChannel: dialerChannel);

      final ans = await service.answerCall();
      expect(ans, isTrue);

      final rej = await service.rejectCall();
      expect(rej, isTrue);

      final end = await service.endCall();
      expect(end, isTrue);

      final mute = await service.setMuted(true);
      expect(mute, isTrue);

      final spk = await service.setSpeaker(true);
      expect(spk, isTrue);

      expect(log.map((c) => c.method), containsAll([
        'answerCall',
        'rejectCall',
        'endCall',
        'setMuted',
        'setSpeaker',
      ]));
    });

    test('call screen controls send their arguments', () async {
      final service = DialerService(methodChannel: dialerChannel);
      await service.holdCall();
      await service.unholdCall();
      await service.swapCalls();
      await service.playDtmf('5');
      await service.stopDtmf();
      await service.selectSim(1);
      expect(log.map((c) => c.method), ['holdCall', 'unholdCall', 'swapCalls', 'playDtmf', 'stopDtmf', 'selectSim']);
      expect(log[3].arguments, {'digit': '5'});
      expect(log[5].arguments, {'index': 1});
    });
  });

  group('CallEvent for the call screen', () {
    test('reads the full call snapshot', () {
      final e = CallEvent.fromMap({
        'event': 'callStateChanged',
        'callId': 'c2',
        'state': 'ACTIVE',
        'phoneNumber': '9944446953',
        'isIncoming': false,
        'connectTimeMillis': 1794913210000,
        'canHold': true,
        'muted': true,
        'audioRoute': 'speaker',
        'otherCalls': 1,
        'heldCalls': 1,
        'simChoices': ['SIM 1 · Jio', 'SIM 2 · Airtel'],
      });
      expect(e.callId, 'c2');
      expect(e.isLive, isTrue);
      expect(e.isRingingIn, isFalse);
      expect(e.connectTimeMillis, 1794913210000);
      expect(e.canHold, isTrue);
      expect(e.muted, isTrue);
      expect(e.speakerOn, isTrue);
      expect(e.heldCalls, 1);
      expect(e.simChoices, hasLength(2));
    });

    test('older / partial events still parse', () {
      final e = CallEvent.fromMap({'state': 'SELECT_SIM'});
      expect(e.state, CallState.selectSim);
      expect(e.simChoices, isEmpty);
      expect(e.speakerOn, isFalse);
      expect(CallEvent.fromMap({'state': 'NEW'}).state, CallState.dialing);
      expect(CallEvent.fromMap({'state': 'DISCONNECTED'}).isLive, isFalse);
    });

    test('status line', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1794913252000);
      String status(Map<String, dynamic> m) => callStatusText(CallEvent.fromMap(m), now);
      expect(status({'state': 'RINGING'}), 'Incoming call');
      expect(status({'state': 'DIALING'}), 'Calling…');
      expect(status({'state': 'SELECT_SIM'}), 'Choose a SIM');
      expect(status({'state': 'ACTIVE', 'connectTimeMillis': 1794913210000}), '00:42');
      expect(status({'state': 'ACTIVE'}), 'Connected');
      expect(status({'state': 'HOLDING'}), 'On hold');
      expect(formatCallTimer(const Duration(hours: 1, minutes: 2, seconds: 5)), '1:02:05');
    });
  });
}
