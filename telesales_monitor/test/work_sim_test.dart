import 'package:flutter_test/flutter_test.dart';
import 'package:telesales_monitor/services/work_sim.dart';

void main() {
  group('isWorkSimCall', () {
    test('registered on SIM 2: SIM 1 calls are dropped, SIM 2 calls kept', () {
      expect(isWorkSimCall(1, 'sim2Only', 2), isFalse);
      expect(isWorkSimCall(2, 'sim2Only', 2), isTrue);
    });

    test('registered on SIM 1: SIM 2 calls are dropped', () {
      expect(isWorkSimCall(2, 'sim1Only', 2), isFalse);
      expect(isWorkSimCall(1, 'sim1Only', 2), isTrue);
    });

    test('unknown SIM on a dual-SIM phone is dropped (may be the personal SIM)', () {
      expect(isWorkSimCall(0, 'sim2Only', 2), isFalse);
      expect(isWorkSimCall(0, 'sim1Only', 2), isFalse);
    });

    test('unknown SIM is kept on a single-SIM phone or when both SIMs are tracked', () {
      expect(isWorkSimCall(0, 'sim1Only', 1), isTrue);
      expect(isWorkSimCall(0, 'bothSims', 2), isTrue);
      expect(isWorkSimCall(0, 'sim2Only', 0), isTrue); // SIM info not readable
    });
  });

  group('pickWorkSimSlot', () {
    test('a SIM whose number matches wins', () {
      expect(pickWorkSimSlot(matchedSlot: 2, savedSlot: 1, detectedSlots: {1, 2}), 2);
    });

    test('remembered choice for this number is used when that SIM is in the phone', () {
      expect(pickWorkSimSlot(savedSlot: 2, detectedSlots: {1, 2}), 2);
      expect(pickWorkSimSlot(savedSlot: 2, detectedSlots: {1}), 1); // SIM 2 removed: the only SIM
    });

    test('single-SIM phone: that SIM', () {
      expect(pickWorkSimSlot(detectedSlots: {2}), 2);
    });

    test('dual-SIM phone that cannot tell: the caller must pick', () {
      expect(pickWorkSimSlot(detectedSlots: {1, 2}), isNull);
    });

    test('SIMs not readable: leave tracking as it is', () {
      expect(pickWorkSimSlot(detectedSlots: <int>{}), -1);
    });
  });
}
