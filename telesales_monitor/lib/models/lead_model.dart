enum LeadStatus {
  won,
  interested,
  followUp,
  notPickup,
  lost,
  renewalFollowUp,
  busyOnCall,
  newLead,
  other,
  notInterested,
}

class LeadModel {
  final String id;
  final String name;
  final String phone;
  LeadStatus status;
  int attempts;
  final DateTime dateAdded;
  DateTime lastCallDate;
  String note;

  LeadModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.status,
    required this.attempts,
    required this.dateAdded,
    required this.lastCallDate,
    required this.note,
  });

  String get statusLabel {
    switch (status) {
      case LeadStatus.won:
        return 'WON';
      case LeadStatus.interested:
        return 'INTERESTED';
      case LeadStatus.followUp:
        return 'FOLLOW-UP CALL';
      case LeadStatus.notPickup:
        return 'NOT PICKUP';
      case LeadStatus.lost:
        return 'LOST';
      case LeadStatus.renewalFollowUp:
        return 'RENEWAL FOLLOW-UP';
      case LeadStatus.busyOnCall:
        return 'BUSY ON CALL';
      case LeadStatus.newLead:
        return 'NEW';
      case LeadStatus.other:
        return 'OTHER';
      case LeadStatus.notInterested:
        return 'NOT INTERESTED';
    }
  }
}
