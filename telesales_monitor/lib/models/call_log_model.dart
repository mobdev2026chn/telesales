enum CallType {
  incoming,
  outgoing,
  missed,
  neverAttended,
  rejected,
}

class CallLogModel {
  final String id;
  final String contactName;
  final String phoneNumber;
  final CallType type;
  final Duration duration;
  final DateTime timestamp;
  final String? note;
  final String? recordingPath;
  final String agentName;
  final int simSlot; // 1 for SIM 1, 2 for SIM 2

  CallLogModel({
    required this.id,
    required this.contactName,
    required this.phoneNumber,
    required this.type,
    required this.duration,
    required this.timestamp,
    this.note,
    this.recordingPath,
    this.agentName = 'Caller Agent',
    this.simSlot = 1,
  });

  String get simBadge => 'SIM $simSlot';

  String get durationFormatted {
    if (type == CallType.missed || type == CallType.neverAttended || type == CallType.rejected) {
      return '0s';
    }
    final m = duration.inMinutes;
    final s = duration.inSeconds % 60;
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String get typeLabel {
    switch (type) {
      case CallType.incoming:
        return 'INCOMING';
      case CallType.outgoing:
        return 'OUTGOING';
      case CallType.missed:
        return 'MISSED';
      case CallType.neverAttended:
        return 'NEVER ATTENDED';
      case CallType.rejected:
        return 'REJECTED';
    }
  }

  String get glyph {
    switch (type) {
      case CallType.incoming:
        return '↙';
      case CallType.outgoing:
        return '↗';
      case CallType.missed:
        return '✕';
      case CallType.neverAttended:
        return '⊘';
      case CallType.rejected:
        return '⛔';
    }
  }
}
