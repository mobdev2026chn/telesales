import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import 'notifications_sheet.dart';
import '../providers/tele_provider.dart';
import '../screens/login_screen.dart';

class TopHeader extends StatelessWidget {
  final String title;
  final String userName;
  final int selectedSimIndex; // 0 = ALL, 1 = SIM 1, 2 = SIM 2
  final ValueChanged<int>? onSimSelected;

  const TopHeader({
    super.key,
    required this.title,
    this.userName = 'ADMIN',
    this.selectedSimIndex = 1,
    this.onSimSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);
    final unreadCount = tele.unreadNotificationCount;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Title & User Name (Auto-scaled to prevent overflow)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title.toUpperCase(),
                      style: AppTheme.headline(size: 23, color: AppTheme.ink900),
                    ),
                    Text(
                      '.',
                      style: AppTheme.headline(size: 23, color: AppTheme.greenNeon),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 1),
              Text(
                userName.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.mono(size: 8.5, color: AppTheme.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),

        // Controls Group (Notifications, SIM Pill, Avatar, Logout)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Notification Bell Button with Badge (Visible ONLY for Callers)
            if (tele.currentRole == UserRole.caller) ...[
              GestureDetector(
                onTap: () {
                  NotificationsSheet.show(context);
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppTheme.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.ink900, width: 1.5),
                        boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                      ),
                      child: const Icon(
                        Icons.notifications_outlined,
                        size: 16,
                        color: AppTheme.ink900,
                      ),
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        top: -3,
                        right: -3,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: AppTheme.orangePill,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.white, width: 1.2),
                          ),
                          constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                          child: Center(
                            child: Text(
                              '$unreadCount',
                              style: AppTheme.label(size: 7.5, color: AppTheme.white),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
            ],

            // SIM Filter Selector Pill (SIM 1 | SIM 2)
            Container(
              height: 30,
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
                  _buildPillItem(context, tele, 'SIM 1', 1),
                  _buildPillItem(context, tele, 'SIM 2', 2),
                ],
              ),
            ),
            const SizedBox(width: 5),

            // User Profile Photo Avatar
            GestureDetector(
              onTap: () {
                tele.setActiveTabIndex(4); // Switch to Profile tab
              },
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppTheme.limeYellow,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.ink900, width: 1.5),
                  boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                ),
                child: ClipOval(
                  child: tele.profilePhotoBase64.isNotEmpty
                      ? Image.memory(
                          base64Decode(tele.profilePhotoBase64.contains(',') ? tele.profilePhotoBase64.split(',').last : tele.profilePhotoBase64),
                          width: 30,
                          height: 30,
                          fit: BoxFit.cover,
                        )
                      : Center(
                          child: Text(
                            tele.currentUserName.isNotEmpty ? tele.currentUserName[0].toUpperCase() : '👤',
                            style: AppTheme.headline(size: 12, color: AppTheme.ink900),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 5),

            // Dedicated Round Logout Button
            GestureDetector(
              onTap: () => _showLogoutConfirmDialog(context, tele),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.ink900, width: 1.5),
                  boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                ),
                child: const Center(
                  child: Icon(
                    Icons.logout_rounded,
                    size: 15,
                    color: AppTheme.ink900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showLogoutConfirmDialog(BuildContext context, TeleProvider tele) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.ink900, width: 2),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.orangePill,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.ink900, width: 1.5),
              ),
              child: const Icon(Icons.logout_rounded, color: AppTheme.white, size: 16),
            ),
            const SizedBox(width: 10),
            Text('LOGOUT', style: AppTheme.headline(size: 18)),
          ],
        ),
        content: Text(
          'Are you sure you want to log out from Ask Eva Telesales?',
          style: AppTheme.body(size: 13, color: AppTheme.ink900),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('CANCEL', style: AppTheme.label(size: 11, color: AppTheme.muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.ink900,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: AppTheme.ink900, width: 1.2),
              ),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              tele.purgeUserSession();
              Navigator.of(context).pushAndRemoveUntil(
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) =>
                      FadeTransition(opacity: animation, child: child),
                  transitionDuration: const Duration(milliseconds: 300),
                ),
                (route) => false,
              );
            },
            child: Text('LOGOUT', style: AppTheme.label(size: 11, color: AppTheme.limeYellow)),
          ),
        ],
      ),
    );
  }

  Widget _buildPillItem(BuildContext context, TeleProvider tele, String label, int index) {
    final isSelected = tele.activeSimSlot == index;
    return GestureDetector(
      onTap: () {
        tele.setActiveSimSlot(index);
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
