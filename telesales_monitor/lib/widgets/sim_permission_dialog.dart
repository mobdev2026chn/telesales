import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'neo_button.dart';

class SimPermissionDialog extends StatelessWidget {
  final int simNumber;
  final String carrierName;
  final VoidCallback onAllow;
  final VoidCallback onDeny;

  const SimPermissionDialog({
    super.key,
    this.simNumber = 2,
    this.carrierName = 'Jio',
    required this.onAllow,
    required this.onDeny,
  });

  static void show(BuildContext context, {int simNumber = 2, String carrierName = 'Jio'}) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) => SimPermissionDialog(
        simNumber: simNumber,
        carrierName: carrierName,
        onAllow: () => Navigator.of(ctx).pop(),
        onDeny: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.paper,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.ink900, width: 2),
          boxShadow: AppTheme.neoShadow(color: AppTheme.ink900, offset: 6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Lock Circle Icon
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppTheme.limeYellow,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.ink900, width: 1.5),
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                size: 26,
                color: AppTheme.ink900,
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              'ALLOW SIM $simNumber ACCESS?',
              style: AppTheme.headline(size: 24, color: AppTheme.ink900),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),

            // Description
            Text(
              'Call Monitor needs permission to read call logs and place calls on SIM $simNumber · $carrierName. Your admin will be notified.',
              style: AppTheme.body(size: 12.5, color: AppTheme.ink700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Action Buttons (DENY | ALLOW)
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onDeny,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppTheme.ink900, width: 1.5),
                      ),
                      child: Center(
                        child: Text(
                          'DENY',
                          style: AppTheme.label(size: 11, color: AppTheme.ink900),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: NeoButton(
                    backgroundColor: AppTheme.greenNeon,
                    shadowColor: AppTheme.ink900,
                    onTap: onAllow,
                    child: Center(
                      child: Text(
                        'ALLOW',
                        style: AppTheme.label(size: 11, color: AppTheme.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
