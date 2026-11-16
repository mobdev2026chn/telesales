import 'dart:async';
import 'package:flutter/services.dart';

/// Represents the lifecycle states of a cellular phone call.
enum CallState {
  none,
  ringing,
  dialing,
  connecting,
  active,
  holding,
  disconnecting,
  disconnected,
}

/// Information about a real-time call event emitted by the native InCallService.
class CallEvent {
  final String event;
  final CallState state;
  final String phoneNumber;
  final String displayName;
  final bool isIncoming;
  final int timestamp;

  const CallEvent({
    required this.event,
    required this.state,
    this.phoneNumber = '',
    this.displayName = '',
    this.isIncoming = false,
    this.timestamp = 0,
  });

  factory CallEvent.fromMap(Map<dynamic, dynamic> map) {
    return CallEvent(
      event: (map['event'] as String?) ?? 'unknown',
      state: _parseCallState(map['state'] as String?),
      phoneNumber: (map['phoneNumber'] as String?) ?? '',
      displayName: (map['displayName'] as String?) ?? '',
      isIncoming: (map['isIncoming'] as bool?) ?? false,
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  static CallState _parseCallState(String? stateStr) {
    switch (stateStr?.toUpperCase()) {
      case 'RINGING':
        return CallState.ringing;
      case 'DIALING':
        return CallState.dialing;
      case 'CONNECTING':
        return CallState.connecting;
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

  @override
  String toString() {
    return 'CallEvent(event: $event, state: $state, number: $phoneNumber, incoming: $isIncoming)';
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

  /// Prompts the Android RoleManager system dialog to request default dialer role.
  /// (Per policy, this should only be called after incoming and ongoing call UI are ready).
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
        .map((event) => CallEvent.fromMap(event as Map<dynamic, dynamic>));
    return _callEventsStream!;
  }

  /// Answers the active incoming call.
  Future<bool> answerCall() async {
    try {
      final bool? res = await _methodChannel.invokeMethod<bool>('answerCall');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Rejects the active incoming call.
  Future<bool> rejectCall() async {
    try {
      final bool? res = await _methodChannel.invokeMethod<bool>('rejectCall');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Ends / disconnects the current active call.
  Future<bool> endCall() async {
    try {
      final bool? res = await _methodChannel.invokeMethod<bool>('endCall');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Mutes or un-mutes microphone during call.
  Future<bool> setMuted(bool muted) async {
    try {
      final bool? res = await _methodChannel.invokeMethod<bool>('setMuted', {'muted': muted});
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Enables or disables speakerphone audio route during call.
  Future<bool> setSpeaker(bool speaker) async {
    try {
      final bool? res = await _methodChannel.invokeMethod<bool>('setSpeaker', {'speaker': speaker});
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
