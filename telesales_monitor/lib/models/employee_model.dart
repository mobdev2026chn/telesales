class EmployeeModel {
  final String id;
  final String name;
  final String phone;
  final String role;
  final int totalCalls;
  final int connectedCalls;
  final Duration totalTalkTime;
  final int incomingCalls;
  final int outgoingCalls;
  final int missedCalls;
  final int neverAttendedCalls;
  final int rank;

  final String? avatarUrl;
  final String? photoBase64;

  EmployeeModel({
    required this.id,
    required this.name,
    required this.phone,
    this.role = 'caller',
    this.avatarUrl,
    this.photoBase64,
    required this.totalCalls,
    required this.connectedCalls,
    required this.totalTalkTime,
    required this.incomingCalls,
    required this.outgoingCalls,
    required this.missedCalls,
    required this.neverAttendedCalls,
    required this.rank,
  });

  String get talkTimeFormatted {
    final h = totalTalkTime.inHours;
    final m = totalTalkTime.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}
