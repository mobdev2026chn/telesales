import 'package:flutter/material.dart';
import '../models/sim_card_info.dart';
import '../theme/app_theme.dart';

/// Asks which SIM holds the caller's registered number (dual-SIM phones that cannot tell by
/// themselves). Returns the 1-based slot, or null when the caller closes the sheet.
/// Only calls on the chosen SIM are tracked, recorded and uploaded.
Future<int?> showWorkSimPicker(BuildContext context, {required List<SimCardInfo> sims, required String registeredPhone}) {
  final last10 = registeredPhone.replaceAll(RegExp(r'\D'), '');
  final shown = last10.length >= 10 ? '+91 ${last10.substring(last10.length - 10)}' : 'your registered number';
  final options = sims.isNotEmpty
      ? (sims.toList()..sort((a, b) => a.slotIndex.compareTo(b.slotIndex)))
      : [
          SimCardInfo(slotIndex: 0, subscriptionId: -1, displayName: 'SIM 1', carrierName: ''),
          SimCardInfo(slotIndex: 1, subscriptionId: -1, displayName: 'SIM 2', carrierName: ''),
        ];

  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppTheme.ink900, width: 2),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppTheme.muted, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.sim_card_outlined, color: AppTheme.greenDark, size: 24),
                const SizedBox(width: 8),
                Expanded(child: Text('WHICH SIM IS YOUR WORK NUMBER?', style: AppTheme.headline(size: 16))),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Choose the SIM that holds $shown. Only calls made and received on this SIM are tracked, '
              'recorded and uploaded. Calls on your other SIM stay on your phone.',
              style: AppTheme.body(size: 12, color: AppTheme.ink700),
            ),
            const SizedBox(height: 16),
            for (final sim in options) ...[
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(ctx).pop(sim.slotIndex + 1),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.ink900, width: 1.5),
                    boxShadow: const [BoxShadow(color: AppTheme.ink900, offset: Offset(3, 3))],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.limeYellow,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.ink900, width: 1.5),
                        ),
                        child: Text('${sim.slotIndex + 1}', style: AppTheme.headline(size: 16)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(sim.slotLabel, style: AppTheme.bodyBold(size: 14)),
                            Text(
                              [
                                if (sim.displayName.isNotEmpty && sim.displayName != sim.slotLabel) sim.displayName,
                                if (sim.carrierName.isNotEmpty && sim.carrierName != 'Carrier' && sim.carrierName != sim.displayName) sim.carrierName,
                                if (sim.phoneNumber.isNotEmpty) sim.phoneNumber,
                              ].join(' · '),
                              style: AppTheme.mono(size: 11, color: AppTheme.muted),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: AppTheme.ink900),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    ),
  );
}
