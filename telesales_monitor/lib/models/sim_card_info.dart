class SimCardInfo {
  final int slotIndex; // 0 for SIM 1, 1 for SIM 2
  final int subscriptionId;
  final String displayName;
  final String carrierName;
  final String phoneNumber;
  final String countryIso;

  SimCardInfo({
    required this.slotIndex,
    required this.subscriptionId,
    required this.displayName,
    required this.carrierName,
    this.phoneNumber = '',
    this.countryIso = '',
  });

  factory SimCardInfo.fromMap(Map<dynamic, dynamic> map) {
    return SimCardInfo(
      slotIndex: (map['slotIndex'] is int) ? map['slotIndex'] as int : 0,
      subscriptionId: (map['subscriptionId'] is int) ? map['subscriptionId'] as int : 1,
      displayName: (map['displayName'] as String?)?.isNotEmpty == true
          ? map['displayName'] as String
          : 'SIM ${((map['slotIndex'] as int? ?? 0) + 1)}',
      carrierName: (map['carrierName'] as String?)?.isNotEmpty == true
          ? map['carrierName'] as String
          : 'Carrier',
      phoneNumber: map['number'] as String? ?? '',
      countryIso: map['countryIso'] as String? ?? '',
    );
  }

  String get slotLabel => 'SIM ${slotIndex + 1}';
  String get titleDisplay => '$slotLabel · $displayName';
}
