enum LeadStatus {
  followUp,
  bookDemo,
  demoReschedule,
  demoDone,
  newFollowUp,
  notPickup,
  busyOnCall,
  renewalFollowUp,
  interested,
  warned,
  lost,
  newLead,
  won,
  notInterested,
  other,
}

class LeadModel {
  final String id;
  String name;
  final String phone;
  LeadStatus status;
  int attempts;
  final DateTime dateAdded;
  DateTime lastCallDate;
  String note;
  String assignedTo; // Scoped to individual caller

  LeadModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.status,
    required this.attempts,
    required this.dateAdded,
    required this.lastCallDate,
    required this.note,
    this.assignedTo = '',
  });

  String get statusLabel {
    switch (status) {
      case LeadStatus.followUp:
        return 'Follow up';
      case LeadStatus.bookDemo:
        return 'Book Demo';
      case LeadStatus.demoReschedule:
        return 'Demo Reschedule';
      case LeadStatus.demoDone:
        return 'Demo Done';
      case LeadStatus.newFollowUp:
        return 'New Follow Up call';
      case LeadStatus.notPickup:
        return 'Not pick up';
      case LeadStatus.busyOnCall:
        return 'Busy on call';
      case LeadStatus.renewalFollowUp:
        return 'Renewal follow up';
      case LeadStatus.interested:
        return 'Interested';
      case LeadStatus.warned:
        return 'Warned';
      case LeadStatus.lost:
        return 'Lost';
      case LeadStatus.newLead:
        return 'New Lead';
      case LeadStatus.won:
        return 'Interested';
      case LeadStatus.notInterested:
        return 'Not Interested';
      case LeadStatus.other:
        return 'Follow up';
    }
  }

  static LeadStatus parseStatus(String str) {
    final lower = str.toLowerCase().trim();
    if (lower.contains('book demo')) return LeadStatus.bookDemo;
    if (lower.contains('reschedule')) return LeadStatus.demoReschedule;
    if (lower.contains('demo done')) return LeadStatus.demoDone;
    if (lower.contains('follow')) return LeadStatus.followUp;
    if (lower.contains('not pick') || lower.contains('no answer')) return LeadStatus.notPickup;
    if (lower.contains('busy')) return LeadStatus.busyOnCall;
    if (lower.contains('renewal')) return LeadStatus.renewalFollowUp;
    if (lower.contains('interested') || lower.contains('won')) return LeadStatus.interested;
    if (lower.contains('warned')) return LeadStatus.warned;
    if (lower.contains('lost') || lower.contains('not interested')) return LeadStatus.notInterested;
    if (lower.contains('new')) return LeadStatus.newLead;
    return LeadStatus.followUp;
  }
}

