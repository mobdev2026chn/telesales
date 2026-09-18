import 'package:flutter_test/flutter_test.dart';
import 'package:telesales_monitor/services/call_recording_setup.dart';

void main() {
  group('shouldRunCallMonitor', () {
    test('runs for a signed-in caller with auto-record on', () {
      expect(
        shouldRunCallMonitor(isLoggedIn: true, isCallerContext: true, autoRecordEnabled: true, authToken: 'eyJ.abc.def'),
        isTrue,
      );
    });

    test('never runs without a session, outside caller context or with auto-record off', () {
      expect(shouldRunCallMonitor(isLoggedIn: false, isCallerContext: true, autoRecordEnabled: true, authToken: 'eyJ'), isFalse);
      expect(shouldRunCallMonitor(isLoggedIn: true, isCallerContext: false, autoRecordEnabled: true, authToken: 'eyJ'), isFalse);
      expect(shouldRunCallMonitor(isLoggedIn: true, isCallerContext: true, autoRecordEnabled: false, authToken: 'eyJ'), isFalse);
      expect(shouldRunCallMonitor(isLoggedIn: true, isCallerContext: true, autoRecordEnabled: true, authToken: ''), isFalse);
    });

    test('legacy fake tokens do not count as a session', () {
      expect(shouldRunCallMonitor(isLoggedIn: true, isCallerContext: true, autoRecordEnabled: true, authToken: 'jwt_123'), isFalse);
    });
  });

  group('legacyUploadsForNative', () {
    test('converts the old Dart pending-upload entries', () {
      final out = legacyUploadsForNative([
        {
          'userId': 'u1',
          'filePath': '/data/user/0/app/files/call_recordings/OUT_CALL_REC_1.wav',
          'fileName': 'OUT_CALL_REC_1.wav',
          'phoneNumber': '9825012340',
          'contactName': 'Ravi',
          'callStartedAt': '2026-09-18T05:30:00.000Z',
          'durationSeconds': 42,
          'type': 'INCOMING',
          'simSlot': 2,
        },
      ]);
      expect(out, hasLength(1));
      final m = out.single;
      expect(m['userId'], 'u1');
      expect(m['fileName'], 'OUT_CALL_REC_1.wav');
      expect(m['callStartedAtMs'], DateTime.utc(2026, 9, 18, 5, 30).millisecondsSinceEpoch);
      expect(m['durationSeconds'], 42);
      expect(m['type'], 'INCOMING');
      expect(m['simSlot'], 2);
    });

    test('drops entries without a user or file and non-map rows', () {
      final out = legacyUploadsForNative([
        {'userId': '', 'filePath': '/x.wav'},
        {'userId': 'u1', 'filePath': ''},
        'garbage',
        null,
      ]);
      expect(out, isEmpty);
    });

    test('fills defaults for missing fields', () {
      final m = legacyUploadsForNative([
        {'userId': 'u1', 'filePath': '/x.wav'},
      ]).single;
      expect(m['type'], 'OUTGOING');
      expect(m['durationSeconds'], 1);
      expect(m['simSlot'], 0);
      expect(m['callStartedAtMs'], isA<int>());
    });
  });

  group('dialerGuideFor', () {
    test('matches brands case-insensitively, by manufacturer or brand', () {
      expect(dialerGuideFor('Xiaomi').brandLabel, contains('Xiaomi'));
      expect(dialerGuideFor('', 'POCO').brandLabel, contains('POCO'));
      expect(dialerGuideFor('samsung').brandLabel, 'Samsung');
      expect(dialerGuideFor('realme').brandLabel, contains('realme'));
      expect(dialerGuideFor('OnePlus').brandLabel, contains('OnePlus'));
      expect(dialerGuideFor('vivo', 'iQOO').brandLabel, contains('vivo'));
      expect(dialerGuideFor('HONOR').brandLabel, contains('Honor'));
      expect(dialerGuideFor('motorola').brandLabel, contains('Motorola'));
      expect(dialerGuideFor('Google').brandLabel, contains('Google'));
      expect(dialerGuideFor('HMD Global', 'Nokia').brandLabel, contains('Nokia'));
      expect(dialerGuideFor('TECNO MOBILE LIMITED').brandLabel, contains('Tecno'));
      expect(dialerGuideFor('INFINIX MOBILITY LIMITED').brandLabel, contains('Infinix'));
      expect(dialerGuideFor('LAVA').brandLabel, 'Lava');
    });

    test('unknown brands get the generic guide', () {
      final g = dialerGuideFor('SomeNewBrand');
      expect(g.brandLabel, 'Your phone');
      expect(g.steps, isNotEmpty);
      expect(g.needsAutostart, isFalse);
    });

    test('autostart note only for OEMs with aggressive background killing', () {
      expect(dialerGuideFor('Xiaomi').needsAutostart, isTrue);
      expect(dialerGuideFor('OPPO').needsAutostart, isTrue);
      expect(dialerGuideFor('vivo').needsAutostart, isTrue);
      expect(dialerGuideFor('realme').needsAutostart, isTrue);
      expect(dialerGuideFor('samsung').needsAutostart, isFalse);
      expect(dialerGuideFor('Google').needsAutostart, isFalse);
    });

    test('every guide has steps', () {
      for (final b in ['xiaomi', 'samsung', 'oppo', 'vivo', 'huawei', 'motorola', 'tecno', 'lava', 'x']) {
        expect(dialerGuideFor(b).steps, isNotEmpty, reason: b);
      }
    });
  });

  test('RecordingSetupStatus.fromMap tolerates missing and mistyped values', () {
    final s = RecordingSetupStatus.fromMap({
      'manufacturer': 'Xiaomi',
      'sdkInt': 34,
      'serviceRunning': true,
      'mediaPermission': 'yes', // not a bool: treated as false
      'pendingUploads': '3',
    });
    expect(s.manufacturer, 'Xiaomi');
    expect(s.sdkInt, 34);
    expect(s.serviceRunning, isTrue);
    expect(s.mediaPermission, isFalse);
    expect(s.nativeRecorderDetected, isFalse);
    expect(s.pendingUploads, 3);
  });
}
