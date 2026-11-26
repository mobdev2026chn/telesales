import 'package:flutter_test/flutter_test.dart';
import 'package:telesales_monitor/services/call_recording_setup.dart';

void main() {
  group('shouldRunCallMonitor',() {
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

  group('Phone by Google', () {
    const google = 'com.google.android.dialer';
    RecordingSetupStatus status(String dialer, [String ownDialer = '', String ownLabel = '']) =>
        RecordingSetupStatus.fromMap({'dialerPackage': dialer, 'builtInDialerPackage': ownDialer, 'builtInDialerLabel': ownLabel});

    test('can be switched away from only when the phone has its own Phone app', () {
      expect(status(google, 'com.samsung.android.dialer').canSwitchFromGoogleDialer, isTrue);
      expect(status(google).canSwitchFromGoogleDialer, isFalse); // Pixel, Motorola, Google-only phones
      expect(status(google).usesGoogleDialer, isTrue);
      expect(status('com.samsung.android.dialer', 'com.samsung.android.dialer').canSwitchFromGoogleDialer, isFalse);
      expect(status('').usesGoogleDialer, isFalse);
    });

    test('names the phone\'s own Phone app, "Phone" when it has no label', () {
      expect(status(google, 'com.android.contacts', 'Contacts & Phone').builtInDialerName, 'Contacts & Phone');
      expect(status(google, 'com.android.contacts').builtInDialerName, 'Phone');
    });

    test('the built-in recorder is not trusted while calls go through it', () {
      const ready = {'micPermission': true, 'phonePermissions': true, 'mediaPermission': true, 'nativeRecorderDetected': true};
      expect(RecordingSetupStatus.fromMap({...ready, 'dialerPackage': 'com.samsung.android.dialer'}).builtInTrusted, isTrue);
      final switched = RecordingSetupStatus.fromMap({...ready, 'dialerPackage': google});
      expect(switched.builtInTrusted, isFalse);
      expect(switched.needsAccessibility, isTrue);
    });

    test('"Use AskEVA as Phone app": offered, with a warning where the phone recorder would stop', () {
      RecordingSetupStatus s(Map<String, dynamic> m) => RecordingSetupStatus.fromMap({'dialerRoleAvailable': true, ...m});
      // Phone by Google only: nothing to lose
      expect(s({'dialerPackage': google}).canOfferAskEvaDialer, isTrue);
      expect(s({'dialerPackage': google}).askevaDialerStopsPhoneRecorder, isFalse);
      // Samsung's own Phone app: allowed, but its recorder stops (the screen warns and asks first)
      expect(s({'dialerPackage': 'com.samsung.android.dialer'}).canOfferAskEvaDialer, isTrue);
      expect(s({'dialerPackage': 'com.samsung.android.dialer'}).askevaDialerStopsPhoneRecorder, isTrue);
      // Phone by Google with the maker's Phone app installed: switching to that one is better
      expect(s({'dialerPackage': google, 'builtInDialerPackage': 'com.samsung.android.dialer'}).canOfferAskEvaDialer, isFalse);
      expect(s({'dialerPackage': google, 'dialerRoleAvailable': false}).canOfferAskEvaDialer, isFalse);
      final already = s({'dialerPackage': 'com.askeva.telesales_monitor', 'askevaIsDialer': true});
      expect(already.canOfferAskEvaDialer, isFalse);
      expect(already.askevaDialerStopsPhoneRecorder, isFalse);
      expect(already.usesGoogleDialer, isFalse);
    });

    test('AskEVA as the Phone app means no phone recorder: AskEVA records (Accessibility needed)', () {
      final s = RecordingSetupStatus.fromMap({
        'micPermission': true, 'phonePermissions': true, 'mediaPermission': true,
        'nativeRecorderDetected': true, // left over from before the switch
        'dialerPackage': 'com.askeva.telesales_monitor', 'askevaIsDialer': true,
      });
      expect(s.builtInTrusted, isFalse);
      expect(s.needsAccessibility, isTrue);
    });
  });

  group('recordingProblemFor (the dashboard banner)', () {
    const ready = {'micPermission': true, 'phonePermissions': true, 'mediaPermission': true, 'accessibilityEnabled': true};
    RecordingProblem? problem(Map<String, dynamic> m, {bool autoRecord = true}) =>
        recordingProblemFor(RecordingSetupStatus.fromMap(m), autoRecordEnabled: autoRecord);

    test('nothing to show without a status, with auto-record off, or when all is well', () {
      expect(recordingProblemFor(null, autoRecordEnabled: true), isNull);
      expect(problem({}, autoRecord: false), isNull);
      expect(problem(ready), isNull);
    });

    test('recording off comes first', () {
      final p = problem({'dialerPackage': 'com.google.android.dialer', 'builtInDialerPackage': 'x'});
      expect(p!.title, 'CALLS ARE NOT BEING RECORDED');
      expect(p.text, contains('off'));
    });

    test('a silent last call', () {
      final p = problem({...ready, 'lastCaptureStatus': 'silent', 'lastCaptureA11y': true});
      expect(p!.text, contains('without sound'));
    });

    test('Phone by Google with the phone\'s own Phone app available: ask to switch, naming it', () {
      final p = problem({
        ...ready,
        'dialerPackage': 'com.google.android.dialer',
        'builtInDialerPackage': 'com.samsung.android.dialer',
        'builtInDialerLabel': 'Phone',
      });
      expect(p!.title, 'CUSTOMER VOICE MAY BE MISSING');
      expect(p.text, contains('"Phone"'));
    });

    test('Phone by Google as the only Phone app: no banner, nothing the caller can change', () {
      expect(problem({...ready, 'dialerPackage': 'com.google.android.dialer'}), isNull);
    });
  });

  group('recordingReady (the one status the setup screen shows)', () {
    const allowed = {'micPermission': true, 'phonePermissions': true, 'mediaPermission': true};

    test('needs every Android permission', () {
      expect(RecordingSetupStatus.fromMap({}).recordingReady, isFalse);
      expect(RecordingSetupStatus.fromMap({...allowed, 'phonePermissions': false, 'accessibilityEnabled': true}).recordingReady, isFalse);
      expect(RecordingSetupStatus.fromMap({...allowed, 'mediaPermission': false, 'accessibilityEnabled': true}).recordingReady, isFalse);
    });

    test('is on with the phone\'s own recorder, without Accessibility', () {
      final s = RecordingSetupStatus.fromMap({...allowed, 'nativeRecorderDetected': true});
      expect(s.builtInTrusted, isTrue);
      expect(s.needsAccessibility, isFalse);
      expect(s.recordingReady, isTrue);
    });

    test('needs Accessibility when AskEVA records calls itself', () {
      expect(RecordingSetupStatus.fromMap(allowed).needsAccessibility, isTrue);
      expect(RecordingSetupStatus.fromMap(allowed).recordingReady, isFalse);
      expect(RecordingSetupStatus.fromMap({...allowed, 'accessibilityEnabled': true}).recordingReady, isTrue);
    });

    test('is on without Accessibility kept on when the app switches it on per call', () {
      final s = RecordingSetupStatus.fromMap({...allowed, 'a11ySelfRepair': true});
      expect(s.needsAccessibility, isFalse);
      expect(s.recordingReady, isTrue);
    });

    test('reads the loudspeaker flag', () {
      expect(RecordingSetupStatus.fromMap({}).speakerFallbackActive, isFalse);
      expect(RecordingSetupStatus.fromMap({'speakerFallbackActive': true}).speakerFallbackActive, isTrue);
    });
  });
}
