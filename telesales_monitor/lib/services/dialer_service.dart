import 'dart:async';
import 'package:flutter/services.dart';

/// Represents the lifecycle states of a cellular phone call.
enum CallState {
  none,
  ringing,
  dialing,
  connecting,
  /// Dual-SIM phone asking which SIM to call with.
  selectSim,
  active,
  holding,
  disconnecting,
  disconnected,
}

/// The call AskEVA's call screen shows, as streamed by the native CallManager while AskEVA is the
/// phone's Phone app. One event per change; [state] disconnected = no calls left.
class CallEvent {
  final String event;
  final CallState state;
  final String phoneNumber;
  final String displayName;
  final bool isIncoming;
  final int timestamp;
  /// Stable for the life of one call ("c1", "c2", ...): a new id is a new call.
  final String callId;
  /// When the call was answered (epoch ms), 0 before that.
  final int connectTimeMillis;
  final bool canHold;
  final bool muted;
  /// "speaker" | "earpiece" | "bluetooth" | "wired" | "" (unknown)
  final String audioRoute;
  /// Other calls going on (call waiting / on hold).
  final int otherCalls;
  final int heldCalls;
  /// SIM choices while [state] is [CallState.selectSim], e.g. "SIM 1 · Jio".
  final List<String> simChoices;

  const CallEvent({
    required this.event,
    required this.state,
    this.phoneNumber = '',
    this.displayName = '',
    this.isIncoming = false,
    this.timestamp = 0,
    this.callId = '',
    this.connectTimeMillis = 0,
    this.canHold = false,
    this.muted = false,
    this.audioRoute = '',
    this.otherCalls = 0,
    this.heldCalls = 0,
    this.simChoices = const [],
  });

  factory CallEvent.fromMap(Map<dynamic, dynamic> map) {
    int asInt(Object? v) => v is num ? v.toInt() : 0;
    return CallEvent(
      event: (map['event'] as String?) ?? 'unknown',
      state: _parseCallState(map['state'] as String?),
      phoneNumber: (map['phoneNumber'] as String?) ?? '',
      displayName: (map['displayName'] as String?) ?? '',
      isIncoming: (map['isIncoming'] as bool?) ?? false,
      timestamp: asInt(map['timestamp']),
      callId: (map['callId'] as String?) ?? '',
      connectTimeMillis: asInt(map['connectTimeMillis']),
      canHold: (map['canHold'] as bool?) ?? false,
      muted: (map['muted'] as bool?) ?? false,
      audioRoute: (map['audioRoute'] as String?) ?? '',
      otherCalls: asInt(map['otherCalls']),
      heldCalls: asInt(map['heldCalls']),
      simChoices: (map['simChoices'] is List) ? (map['simChoices'] as List).map((e) => e.toString()).toList() : const [],
    );
  }

  static CallState _parseCallState(String? stateStr) {
    switch (stateStr?.toUpperCase()) {
      case 'RINGING':
        return CallState.ringing;
      case 'NEW':
      case 'DIALING':
        return CallState.dialing;
      case 'CONNECTING':
        return CallState.connecting;
      case 'SELECT_SIM':
        return CallState.selectSim;
      case 'ACTIVE':
        return CallState.active;
      case 'HOLDING':
        return CallState.holding;
      case 'DISCONNECTING':
        return CallState.disconnecting;
      case 'DISCONNECTED':
        return CallState.disconnected;
      default:
        return CallState.none;
    }
  }

  /// A call is going on (the call screen or its "return to call" bar is shown).
  bool get isLive => state != CallState.none && state != CallState.disconnected;

  /// Ringing for us: Answer / Decline.
  bool get isRingingIn => state == CallState.ringing;

  bool get speakerOn => audioRoute == 'speaker';

  @override
  String toString() {
    return 'CallEvent(event: $event, state: $state, number: $phoneNumber, incoming: $isIncoming)';
  }
}

/// "00:42" / "1:02:05" talk time.
String formatCallTimer(Duration d) {
  final h = d.inHours;
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// The status line of the call screen: "Incoming call", "Calling…", "00:42", "On hold", ...
String callStatusText(CallEvent e, DateTime now) {
  switch (e.state) {
    case CallState.ringing:
      return 'Incoming call';
    case CallState.dialing:
    case CallState.connecting:
      return 'Calling…';
    case CallState.selectSim:
      return 'Choose a SIM';
    case CallState.active:
      if (e.connectTimeMillis <= 0) return 'Connected';
      final since = now.difference(DateTime.fromMillisecondsSinceEpoch(e.connectTimeMillis));
      return formatCallTimer(since.isNegative ? Duration.zero : since);
    case CallState.holding:
      return 'On hold';
    case CallState.disconnecting:
    case CallState.disconnected:
      return 'Call ended';
    case CallState.none:
      return '';
  }
}

/// Represents whether AskEVA is currently default dialer and if the role is available.
class DialerStatus {
  final bool isDefault;
  final bool isRoleAvailable;

  const DialerStatus({
    required this.isDefault,
    required this.isRoleAvailable,
  });

  factory DialerStatus.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const DialerStatus(isDefault: false, isRoleAvailable: false);
    }
    return DialerStatus(
      isDefault: (map['isDefault'] as bool?) ?? false,
      isRoleAvailable: (map['isRoleAvailable'] as bool?) ?? false,
    );
  }
}

/// Flutter service managing default dialer queries and real-time InCallService events.
class DialerService {
  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  Stream<CallEvent>? _callEventsStream;
  StreamController<void>? _dialRequests;

  DialerService({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel = methodChannel ?? const MethodChannel('com.askeva.telesales/dialer'),
        _eventChannel = eventChannel ?? const EventChannel('com.askeva.telesales/call_events');

  static final DialerService instance = DialerService();

  /// Queries Android RoleManager / TelecomManager to check default dialer status.
  Future<DialerStatus> getDialerStatus() async {
    try {
      final Map<dynamic, dynamic>? res = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('getDialerStatus');
      return DialerStatus.fromMap(res);
    } catch (_) {
      return const DialerStatus(isDefault: false, isRoleAvailable: false);
    }
  }

  /// Asks Android to make AskEVA the phone's Phone app (system dialog). True when it now is.
  Future<bool> requestDefaultDialerRole() async {
    try {
      final bool? res = await _methodChannel.invokeMethod<bool>('requestDefaultDialerRole');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Stream of real-time call state events originating from native InCallService.
  Stream<CallEvent> get callEvents {
    _callEventsStream ??= _eventChannel
        .receiveBroadcastStream()
        .where((event) => event is Map)
        .map((event) => CallEvent.fromMap(event as Map<dynamic, dynamic>))
        .asBroadcastStream();
    return _callEventsStream!;
  }

  /// Fires when a tel: link or the dial pad was opened from another app (AskEVA as the Phone app);
  /// the number is then read with [takePendingDial].
  Stream<void> get dialRequests {
    if (_dialRequests == null) {
      _dialRequests = StreamController<void>.broadcast();
      _methodChannel.setMethodCallHandler((call) async {
        if (call.method == 'dialRequested') _dialRequests?.add(null);
        return null;
      });
    }
    return _dialRequests!.stream;
  }

  /// The number of the last dial request ("" = just open the keypad), null when there is none.
  Future<String?> takePendingDial() async {
    try {
      return await _methodChannel.invokeMethod<String>('takePendingDial');
    } catch (_) {
      return null;
    }
  }

  Future<bool> _call(String method, [Map<String, dynamic>? args]) async {
    try {
      final bool? res = await _methodChannel.invokeMethod<bool>(method, args);
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Answers the ringing call.
  Future<bool> answerCall() => _call('answerCall');

  /// Declines the ringing call.
  Future<bool> rejectCall() => _call('rejectCall');

  /// Ends the call on screen.
  Future<bool> endCall() => _call('endCall');

  /// Mutes or un-mutes microphone during call.
  Future<bool> setMuted(bool muted) => _call('setMuted', {'muted': muted});

  /// Loudspeaker on, or back to the earpiece.
  Future<bool> setSpeaker(bool speaker) => _call('setSpeaker', {'speaker': speaker});

  Future<bool> holdCall() => _call('holdCall');

  Future<bool> unholdCall() => _call('unholdCall');

  /// One call active, one on hold: switch between them.
  Future<bool> swapCalls() => _call('swapCalls');

  /// In-call keypad (IVR menus): a key press is [playDtmf] then [stopDtmf].
  Future<bool> playDtmf(String digit) => _call('playDtmf', {'digit': digit});

  Future<bool> stopDtmf() => _call('stopDtmf');

  /// Dual-SIM phone asking which SIM to use: index into [CallEvent.simChoices].
  Future<bool> selectSim(int index) => _call('selectSim', {'index': index});
}
