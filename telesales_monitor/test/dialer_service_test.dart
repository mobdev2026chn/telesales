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
  });
}
