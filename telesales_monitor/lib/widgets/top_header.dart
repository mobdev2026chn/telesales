import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import 'sim_permission_dialog.dart';
import '../providers/tele_provider.dart';

class TopHeader extends StatelessWidget {
  final String title;
  final String userName;
  final int selectedSimIndex; // 0 = ALL, 1 = SIM 1, 2 = SIM 2
  final ValueChanged<int>? onSimSelected;

  const TopHeader({
    super.key,
    required this.title,
    this.userName = 'RASMI DESAI',
    this.selectedSimIndex = 1,
    this.onSimSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context, listen: false);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title & User Name
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title.toUpperCase(),
                  style: AppTheme.headline(size: 26, color: AppTheme.ink900),
                ),
                Text(
                  '.',
                  style: AppTheme.headline(size: 26, color: AppTheme.greenNeon),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Text(
              userName.toUpperCase(),
              style: AppTheme.mono(size: 9, color: AppTheme.muted),
            ),
          ],
        ),

        // SIM Filter Selector Pill + Direct Logout Phone Icon Button
        Container(
          height: 32,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: AppTheme.paper,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppTheme.ink900, width: 1.5),
            boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPillItem(context, 'ALL', 0),
              _buildPillItem(context, 'SIM 1', 1),
              _buildPillItem(context, 'SIM 2', 2),
              const SizedBox(width: 2),
              GestureDetector(
                onTap: () {
                  tele.logout();
                },
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppTheme.greenNeon,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.ink900, width: 1),
                  ),
                  child: const Icon(
                    Icons.phone_android_rounded,
                    size: 13,
                    color: AppTheme.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPillItem(BuildContext context, String label, int index) {
    final isSelected = selectedSimIndex == index;
    return GestureDetector(
      onTap: () {
        if (index == 2) {
          SimPermissionDialog.show(context, simNumber: 2, carrierName: 'Jio');
        }
        onSimSelected?.call(index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.ink900 : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: AppTheme.label(
            size: 9,
            color: isSelected ? AppTheme.limeYellow : AppTheme.ink900,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }
}
