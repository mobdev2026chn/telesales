import 'package:flutter/services.dart';
import 'api_parsers.dart';

/// Native call monitor (Android): foreground service that follows calls, finds the phone's own
/// call recording (or records the mic as a fallback) and uploads it from a native queue.
/// Dart only starts / stops it and shows its status. See android/.../CallMonitorService.kt.
class CallRecordingChannel {
  static const MethodChannel _channel = MethodChannel('com.askeva.telesales/telephony');

  static Future<bool> startMonitor({required String baseUrl}) async {
    try {
      return await _channel.invokeMethod<bool>('startCallMonitor', {'baseUrl': baseUrl}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stopMonitor() async {
    try {
      await _channel.invokeMethod('stopCallMonitor');
    } catch (_) {}
  }

  static Future<void> retryUploads() async {
    try {
      await _channel.invokeMethod('retryUploads');
    } catch (_) {}
  }

  static Future<int> pendingUploadCount(String userId) async {
    try {
      return await _channel.invokeMethod<int>('getPendingUploadCount', {'userId': userId}) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> enqueueLegacyUploads(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return 0;
    try {
      return await _channel.invokeMethod<int>('enqueueLegacyUploads', {'items': items}) ?? 0;
    } catch (_) {
      return -1;
    }
  }

  static Future<RecordingSetupStatus?> status(String userId) async {
    try {
      final raw = await _channel.invokeMethod('getRecordingSetupStatus', {'userId': userId});
      if (raw is Map) return RecordingSetupStatus.fromMap(Map<String, dynamic>.from(raw));
    } catch (_) {}
    return null;
  }

  static Future<bool> _call(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestMediaPermission() => _call('requestMediaPermission');
  static Future<bool> requestIgnoreBatteryOptimizations() => _call('requestIgnoreBatteryOptimizations');
  static Future<bool> openDialerRecordingSettings() => _call('openDialerRecordingSettings');
  static Future<bool> openAutostartSettings() => _call('openAutostartSettings');
  static Future<bool> openAccessibilitySettings() => _call('openAccessibilitySettings');
  static Future<bool> openAppInfo() => _call('openAppInfo');
  static Future<bool> openDefaultAppsSettings() => _call('openDefaultAppsSettings');
}

class RecordingSetupStatus {
  final String manufacturer;
  final String brand;
  final String model;
  final int sdkInt;
  final bool serviceRunning;
  final bool micPermission;
  final bool mediaPermission;
  final bool batteryOptimizationIgnored;
  final bool nativeRecorderDetected;
  final int pendingUploads;
  /// "AskEVA Call Recording" accessibility service switched on (exempts us from the in-call mic mute).
  final bool accessibilityEnabled;
  /// Our own recording of the last connected work call: "ok", "silent" or "" (none yet).
  final String lastCaptureStatus;
  final DateTime? lastCaptureAt;
  /// Whether Accessibility was on during that last call.
  final bool lastCaptureA11y;
  /// The app may switch Accessibility back on by itself (WRITE_SECURE_SETTINGS granted via adb).
  final bool a11ySelfRepair;
  /// Package of the default Phone app, e.g. "com.google.android.dialer".
  final String dialerPackage;
  /// The loudspeaker will be used on the next work call (no usable built-in recorder on this phone).
  final bool speakerFallbackActive;
  /// Phone state + call log: needed to follow calls and match them to recordings.
  final bool phonePermissions;
  /// The phone maker's own Phone app when it is installed next to "Phone by Google" (package / name
  /// shown to the caller), "" when there is none (Pixel, Motorola, Nokia, phones shipping only Google's).
  final String builtInDialerPackage;
  final String builtInDialerLabel;
  /// AskEVA itself is the phone's Phone app (its own call screen; no phone recorder then).
  final bool askevaIsDialer;
  /// Android lets apps become the Phone app on this phone.
  final bool dialerRoleAvailable;

  static const String googleDialerPackage = 'com.google.android.dialer';

  /// The phone's own recorder was found working, AskEVA may read its files, and calls still go through
  /// that Phone app (not "Phone by Google", whose recordings are private, nor AskEVA itself). Same rule
  /// as the native CallMonitorStore.builtInTrusted.
  bool get builtInTrusted => nativeRecorderDetected && mediaPermission && !usesGoogleDialer && !askevaIsDialer;

  /// AskEVA records calls itself here, which needs the Accessibility service (in-call mic + loudspeaker).
  /// Not when the app may switch it on per call by itself ([a11ySelfRepair]): then it stays off between
  /// calls, so payment apps (GPay, PhonePe) keep working.
  bool get needsAccessibility => !builtInTrusted && !a11ySelfRepair;

  /// Every Android permission the recording needs.
  bool get permissionsGranted => micPermission && phonePermissions && mediaPermission;

  /// Work calls are recorded with both voices: the one status the setup screen shows.
  bool get recordingReady => permissionsGranted && (!needsAccessibility || accessibilityEnabled);

  /// "Phone by Google" keeps its recordings inside its own private storage, where AskEVA cannot
  /// read them: AskEVA can only record the call through the microphone (+ loudspeaker).
  bool get usesGoogleDialer => dialerPackage == googleDialerPackage;

  /// The phone also has its maker's own Phone app, which saves readable recordings (both voices):
  /// making it the default Phone app fixes recording.
  bool get canSwitchFromGoogleDialer => usesGoogleDialer && builtInDialerPackage.isNotEmpty;

  /// Name of the phone's own Phone app for the caller ("Phone" is what most makers call it).
  String get builtInDialerName => builtInDialerLabel.isNotEmpty ? builtInDialerLabel : 'Phone';

  /// "Use AskEVA as Phone app" (AskEVA's own call screen). Not offered where Phone by Google is used but
  /// the maker's Phone app exists: switching to that one is better (it records both voices).
  bool get canOfferAskEvaDialer => !askevaIsDialer && dialerRoleAvailable && !canSwitchFromGoogleDialer;

  /// Becoming the Phone app stops the current Phone app's recorder (Samsung, vivo, ...): calls are then
  /// recorded only through AskEVA's microphone + loudspeaker. Not the case for Phone by Google (private).
  bool get askevaDialerStopsPhoneRecorder => !askevaIsDialer && !usesGoogleDialer;

  const RecordingSetupStatus({
    required this.manufacturer,
    required this.brand,
    required this.model,
    required this.sdkInt,
    required this.serviceRunning,
    required this.micPermission,
    required this.mediaPermission,
    required this.batteryOptimizationIgnored,
    required this.nativeRecorderDetected,
    required this.pendingUploads,
    this.accessibilityEnabled = false,
    this.lastCaptureStatus = '',
    this.lastCaptureAt,
    this.lastCaptureA11y = true,
    this.a11ySelfRepair = false,
    this.dialerPackage = '',
    this.speakerFallbackActive = false,
    this.phonePermissions = false,
    this.builtInDialerPackage = '',
    this.builtInDialerLabel = '',
    this.askevaIsDialer = false,
    this.dialerRoleAvailable = false,
  });

  factory RecordingSetupStatus.fromMap(Map<String, dynamic> m) => RecordingSetupStatus(
        manufacturer: asString(m['manufacturer']),
        brand: asString(m['brand']),
        model: asString(m['model']),
        sdkInt: asInt(m['sdkInt']),
        serviceRunning: m['serviceRunning'] == true,
        micPermission: m['micPermission'] == true,
        mediaPermission: m['mediaPermission'] == true,
        batteryOptimizationIgnored: m['batteryOptimizationIgnored'] == true,
        nativeRecorderDetected: m['nativeRecorderDetected'] == true,
        pendingUploads: asInt(m['pendingUploads']),
        accessibilityEnabled: m['accessibilityEnabled'] == true,
        lastCaptureStatus: asString(m['lastCaptureStatus']),
        lastCaptureAt: asInt(m['lastCaptureAt']) > 0
            ? DateTime.fromMillisecondsSinceEpoch(asInt(m['lastCaptureAt']))
            : null,
        lastCaptureA11y: m['lastCaptureA11y'] == true,
        a11ySelfRepair: m['a11ySelfRepair'] == true,
        dialerPackage: asString(m['dialerPackage']),
        speakerFallbackActive: m['speakerFallbackActive'] == true,
        phonePermissions: m['phonePermissions'] == true,
        builtInDialerPackage: asString(m['builtInDialerPackage']),
        builtInDialerLabel: asString(m['builtInDialerLabel']),
        askevaIsDialer: m['askevaIsDialer'] == true,
        dialerRoleAvailable: m['dialerRoleAvailable'] == true,
      );
}

/// What the dashboard banner says when calls are not recorded properly.
class RecordingProblem {
  final String title;
  final String text;
  const RecordingProblem(this.title, this.text);
}

/// Why calls are probably not recorded properly, most urgent first; null when recording looks fine.
/// A phone that only has "Phone by Google" gets no banner: there is nothing the caller can change
/// (AskEVA already uses the loudspeaker there).
RecordingProblem? recordingProblemFor(RecordingSetupStatus? s, {required bool autoRecordEnabled}) {
  if (s == null || !autoRecordEnabled) return null;
  if (!s.recordingReady) {
    return const RecordingProblem('CALLS ARE NOT BEING RECORDED', 'Call recording is off. Tap once to turn it on.');
  }
  // Silent even though everything was on during the call: a real problem. A silent call made while
  // Accessibility was off is fixed now that it is on (the next call shows whether recording works).
  if (!s.builtInTrusted && s.lastCaptureStatus == 'silent' && s.lastCaptureA11y) {
    return const RecordingProblem(
      'CALLS ARE NOT BEING RECORDED',
      'Your last call was recorded without sound. Tap to check call recording.',
    );
  }
  if (s.canSwitchFromGoogleDialer) {
    return RecordingProblem(
      'CUSTOMER VOICE MAY BE MISSING',
      '"Phone by Google" hides its call recordings. Tap to switch to your phone\'s own '
          '"${s.builtInDialerName}" app so calls are recorded with both voices.',
    );
  }
  return null;
}

/// Whether the call monitor should run: a signed-in caller (or manager in caller mode) with a
/// real session token and auto-record switched on.
bool shouldRunCallMonitor({
  required bool isLoggedIn,
  required bool isCallerContext,
  required bool autoRecordEnabled,
  required String authToken,
}) {
  return isLoggedIn && isCallerContext && autoRecordEnabled && authToken.isNotEmpty && !authToken.startsWith('jwt_');
}

/// Converts the old Dart pending-upload list (prefs key `pending_recording_uploads`) into the
/// native queue's format. Entries without a user or file are dropped.
List<Map<String, dynamic>> legacyUploadsForNative(List<dynamic> legacy) {
  final out = <Map<String, dynamic>>[];
  for (final raw in legacy) {
    if (raw is! Map) continue;
    final m = Map<String, dynamic>.from(raw);
    final userId = asString(m['userId']);
    final path = asString(m['filePath']);
    if (userId.isEmpty || path.isEmpty) continue;
    final started = parseServerDate(m['callStartedAt']);
    out.add({
      'userId': userId,
      'filePath': path,
      'fileName': asString(m['fileName']),
      'phoneNumber': asString(m['phoneNumber']),
      'contactName': asString(m['contactName']),
      'callStartedAtMs': (started ?? DateTime.now()).millisecondsSinceEpoch,
      'durationSeconds': asInt(m['durationSeconds'], 1),
      'type': asString(m['type'], 'OUTGOING'),
      'simSlot': asInt(m['simSlot']),
    });
  }
  return out;
}

/// Brand-specific instructions for turning on the dialer's automatic call recording.
class DialerRecordingGuide {
  final String brandLabel;
  final List<String> steps;
  final String? note;
  /// OEM battery / "autostart" manager that kills background apps unless the app is allowed.
  final bool needsAutostart;

  const DialerRecordingGuide({
    required this.brandLabel,
    required this.steps,
    this.note,
    this.needsAutostart = false,
  });
}

const String _googleDialerNote =
    'If your phone uses the Google "Phone by Google" app, its recordings are kept inside that app and '
    'AskEVA may not be able to find them. The status below shows "Built-in recorder detected" once AskEVA '
    'has found a recording after a call.';

DialerRecordingGuide dialerGuideFor(String manufacturer, [String brand = '']) {
  final m = '${manufacturer.toLowerCase()} ${brand.toLowerCase()}';
  bool has(String s) => m.contains(s);

  if (has('xiaomi') || has('redmi') || has('poco')) {
    return const DialerRecordingGuide(
      brandLabel: 'Xiaomi / Redmi / POCO',
      steps: [
        'Open the Phone app and tap ⋮ (or the settings icon).',
        'Go to Settings → Call recording.',
        'Turn on "Record calls automatically".',
        'Choose "All numbers".',
      ],
      note: _googleDialerNote,
      needsAutostart: true,
    );
  }
  if (has('samsung')) {
    return const DialerRecordingGuide(
      brandLabel: 'Samsung',
      steps: [
        'Open the Phone app and tap ⋮ → Settings.',
        'Tap "Record calls".',
        'Turn on "Auto record calls".',
        'Choose "All calls".',
      ],
    );
  }
  if (has('oppo') || has('realme') || has('oneplus')) {
    return const DialerRecordingGuide(
      brandLabel: 'OPPO / realme / OnePlus',
      steps: [
        'Open the Phone app and tap ⋮ → Settings.',
        'Tap "Call recording".',
        'Turn on "Auto-record calls" (or "Record all calls").',
        'Choose "All calls".',
      ],
      note: _googleDialerNote,
      needsAutostart: true,
    );
  }
  if (has('vivo') || has('iqoo')) {
    return const DialerRecordingGuide(
      brandLabel: 'vivo / iQOO',
      steps: [
        'Open the Phone app and tap Settings (⋮ or the gear icon).',
        'Tap "Call recording".',
        'Turn on "Auto record calls".',
        'Choose "All calls".',
      ],
      note: _googleDialerNote,
      needsAutostart: true,
    );
  }
  if (has('huawei') || has('honor')) {
    return const DialerRecordingGuide(
      brandLabel: 'Huawei / Honor',
      steps: [
        'Open the Phone app and tap ⋮ → Settings.',
        'Tap "Auto-record calls" (or "Call recording").',
        'Turn it on and choose "All calls".',
      ],
      needsAutostart: true,
    );
  }
  if (has('motorola') || has('google') || has('nokia') || has('hmd')) {
    return const DialerRecordingGuide(
      brandLabel: 'Motorola / Google / Nokia (Phone by Google)',
      steps: [
        'Open the Phone app and tap ⋮ → Settings.',
        'Tap "Call recording".',
        'Under "Always record", turn on "Numbers not in your contacts" and add your saved contacts as needed.',
      ],
      note: _googleDialerNote,
    );
  }
  if (has('tecno') || has('infinix') || has('itel') || has('transsion')) {
    return const DialerRecordingGuide(
      brandLabel: 'Tecno / Infinix / itel',
      steps: [
        'Open the Phone app and tap ⋮ → Settings.',
        'Tap "Call recording" (or "Call settings → Call recording").',
        'Turn on "Auto call recording" and choose "All calls".',
      ],
      needsAutostart: true,
    );
  }
  if (has('lava')) {
    return const DialerRecordingGuide(
      brandLabel: 'Lava',
      steps: [
        'Open the Phone app and tap ⋮ → Settings.',
        'Tap "Call recording".',
        'Turn on automatic recording for all calls.',
      ],
      note: _googleDialerNote,
    );
  }
  return const DialerRecordingGuide(
    brandLabel: 'Your phone',
    steps: [
      'Open the Phone (dialer) app and tap ⋮ → Settings.',
      'Look for "Call recording" or "Record calls".',
      'Turn on automatic recording and choose "All calls".',
    ],
    note: _googleDialerNote,
  );
}
