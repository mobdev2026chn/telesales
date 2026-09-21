// Rules for the work SIM: the SIM that holds the caller's registered number. Only calls on it are
// tracked, recorded and uploaded. Mirrors CallMonitorStore.isWorkSim on the Android side.

/// Whether a call on [slot] (1-based, 0 = the phone could not tell) belongs to the work SIM.
/// [modeName] is SimTrackingMode.name: "sim1Only" | "sim2Only" | "bothSims".
/// An unknown slot is kept only when both SIMs are tracked or the phone has a single SIM; on a
/// dual-SIM phone it may be the personal SIM, so it is dropped.
bool isWorkSimCall(int slot, String modeName, int activeSimCount) {
  if (slot <= 0) return modeName == 'bothSims' || activeSimCount <= 1;
  switch (modeName) {
    case 'sim1Only':
      return slot == 1;
    case 'sim2Only':
      return slot == 2;
    default:
      return true;
  }
}

/// The work SIM slot (1-based) for a registered number:
///  1. the SIM whose number matches the registered number ([matchedSlot]),
///  2. the caller's remembered choice ([savedSlot]) when that SIM is still in the phone,
///  3. the phone's only SIM.
/// -1 = the SIMs cannot be read (tracking left as it is). Null = dual-SIM phone that cannot tell:
/// the caller has to pick.
int? pickWorkSimSlot({int? matchedSlot, int? savedSlot, required Set<int> detectedSlots}) {
  if (matchedSlot != null && matchedSlot > 0) return matchedSlot;
  if (savedSlot != null && (savedSlot == 1 || savedSlot == 2) && (detectedSlots.isEmpty || detectedSlots.contains(savedSlot))) {
    return savedSlot;
  }
  if (detectedSlots.length == 1) return detectedSlots.first;
  if (detectedSlots.isEmpty) return -1;
  return null;
}
