import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/tele_provider.dart';
import '../screens/login_screen.dart';
import '../screens/setup/call_recording_setup_screen.dart';

class ProfileMenuSheet {
  static void show(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context, listen: false);
    final callerName = tele.callerName.isNotEmpty ? tele.callerName : 'Caller';
    final phoneStr = tele.verifiedTrackingNumber.isNotEmpty ? tele.verifiedTrackingNumber : '—';
    final simStr = tele.activeSimLabel;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              decoration: BoxDecoration(
                color: AppTheme.paper,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: AppTheme.ink900, width: 2),
                boxShadow: AppTheme.neoShadow(color: AppTheme.ink900),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.ink900.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // User Info Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.ink900,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.ink900, width: 1.5),
                      boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                    ),
                    child: Row(
                      children: [
                        // Avatar Circle
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: AppTheme.greenNeon,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.paper, width: 2),
                          ),
                          child: ClipOval(
                            child: tele.profilePhotoBase64.isNotEmpty
                                ? Image.memory(
                                    base64Decode(tele.profilePhotoBase64.contains(',')
                                        ? tele.profilePhotoBase64.split(',').last
                                        : tele.profilePhotoBase64),
                                    width: 46,
                                    height: 46,
                                    fit: BoxFit.cover,
                                  )
                                : Center(
                                    child: Text(
                                      callerName.isNotEmpty ? callerName[0].toUpperCase() : '👤',
                                      style: AppTheme.headline(size: 20, color: AppTheme.ink900),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                callerName.toUpperCase(),
                                style: AppTheme.headline(size: 16, color: AppTheme.paper),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$phoneStr · $simStr',
                                style: AppTheme.mono(size: 10, color: AppTheme.white),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Menu Items
                  _menuItem(
                    icon: Icons.person_outline,
                    title: 'VIEW PROFILE',
                    subtitle: 'View caller performance & personal details',
                    onTap: () {
                      Navigator.pop(ctx);
                      tele.setActiveTabIndex(4); // Switch to Profile tab
                    },
                  ),
                  const SizedBox(height: 10),

                  _menuItem(
                    icon: Icons.settings_outlined,
                    title: 'SETTINGS',
                    subtitle: 'Call recording setup, permissions & dialer',
                    badge: 'SETUP',
                    badgeColor: AppTheme.greenNeon,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CallRecordingSetupScreen()),
                      );
                      if (context.mounted) {
                        await tele.refreshRecordingSetupStatus();
                      }
                    },
                  ),
                  const SizedBox(height: 10),

                  _menuItem(
                    icon: Icons.logout_rounded,
                    title: 'SIGNOUT',
                    subtitle: 'Logout from AskEVA Telesales',
                    isDanger: true,
                    onTap: () {
                      Navigator.pop(ctx);
                      showLogoutConfirmDialog(context, tele);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _menuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? badge,
    Color? badgeColor,
    bool isDanger = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDanger ? AppTheme.redMissed.withValues(alpha: 0.08) : AppTheme.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDanger ? AppTheme.redMissed : AppTheme.ink900,
            width: 1.5,
          ),
          boxShadow: AppTheme.neoShadowSm(
            color: isDanger ? AppTheme.redMissed.withValues(alpha: 0.3) : AppTheme.ink900,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDanger ? AppTheme.redMissed.withValues(alpha: 0.15) : AppTheme.paper,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDanger ? AppTheme.redMissed : AppTheme.ink900,
                  width: 1.2,
                ),
              ),
              child: Icon(
                icon,
                size: 18,
                color: isDanger ? AppTheme.redMissed : AppTheme.ink900,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: AppTheme.label(
                          size: 11,
                          color: isDanger ? AppTheme.redMissed : AppTheme.ink900,
                          letterSpacing: 0.14,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeColor ?? AppTheme.greenNeon,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppTheme.ink900, width: 1),
                          ),
                          child: Text(
                            badge,
                            style: AppTheme.label(size: 7.5, color: AppTheme.ink900),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTheme.body(size: 11, color: AppTheme.muted),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: isDanger ? AppTheme.redMissed : AppTheme.ink900,
            ),
          ],
        ),
      ),
    );
  }

  static void showLogoutConfirmDialog(BuildContext context, TeleProvider tele) {
    showDialog(
      context: context,
      builder: (ctx) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: AlertDialog(
            backgroundColor: AppTheme.paper,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppTheme.ink900, width: 2),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.redMissed,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.ink900, width: 1.5),
                  ),
                  child: const Icon(Icons.logout_rounded, size: 16, color: AppTheme.white),
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
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  Navigator.of(ctx).pop();
                  final loggedOut = await tele.logout();
                  if (!loggedOut) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not log out. Please check your connection and try again.')),
                    );
                    return;
                  }
                  if (!context.mounted) return;
                  navigator.pushAndRemoveUntil(
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
        ),
      ),
    );
  }
}
