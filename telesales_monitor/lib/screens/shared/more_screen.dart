import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../widgets/top_header.dart';
import '../../providers/tele_provider.dart';
import '../login_screen.dart';

class MoreScreen extends StatefulWidget {
  final VoidCallback onNavigateToBoard;
  const MoreScreen({super.key, required this.onNavigateToBoard});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  bool _isReportSent = false;
  bool _showBanner = false;
  DateTimeRange? _reportDateRange;

  Future<void> _selectReportDateRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: _reportDateRange ?? DateTimeRange(
        start: now.subtract(const Duration(days: 7)),
        end: now,
      ),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.ink900,
              onPrimary: AppTheme.limeYellow,
              surface: AppTheme.white,
              onSurface: AppTheme.ink900,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _reportDateRange = picked);
    }
  }

  void _triggerExport() {
    setState(() {
      _isReportSent = true;
      _showBanner = true;
    });

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _showBanner = false;
          _isReportSent = false;
        });
      }
    });
  }

  void _showManagerPhotoPicker(BuildContext context, TeleProvider tele) {
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.paper,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppTheme.ink900, width: 2),
            boxShadow: AppTheme.neoShadow(color: AppTheme.ink900),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.ink900,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'SET PROFILE PHOTO / AVATAR',
                style: AppTheme.headline(size: 14, color: AppTheme.ink900),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        Navigator.pop(ctx);
                        final ok = await tele.pickAndSaveProfilePhoto(source: ImageSource.gallery);
                        if (ok) {
                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: AppTheme.ink900,
                              content: Text('✓ Profile photo updated successfully!', style: AppTheme.bodyBold(size: 12, color: AppTheme.greenNeon)),
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: AppTheme.limeYellow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.ink900, width: 1.5),
                          boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.photo_library_rounded, size: 18, color: AppTheme.ink900),
                            const SizedBox(width: 8),
                            Text('CHOOSE PHOTO', style: AppTheme.label(size: 9.5, color: AppTheme.ink900, letterSpacing: 0.12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        Navigator.pop(ctx);
                        final ok = await tele.pickAndSaveProfilePhoto(source: ImageSource.camera);
                        if (ok) {
                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: AppTheme.ink900,
                              content: Text('✓ Profile photo taken successfully!', style: AppTheme.bodyBold(size: 12, color: AppTheme.greenNeon)),
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: AppTheme.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.ink900, width: 1.5),
                          boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.camera_alt_rounded, size: 18, color: AppTheme.ink900),
                            const SizedBox(width: 8),
                            Text('TAKE PHOTO', style: AppTheme.label(size: 9.5, color: AppTheme.ink900, letterSpacing: 0.12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (tele.profilePhotoBase64.isNotEmpty || tele.profilePhotoPath.isNotEmpty) ...[
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () async {
                    Navigator.pop(ctx);
                    await tele.clearProfilePhoto();
                    messenger.showSnackBar(
                      SnackBar(
                        backgroundColor: AppTheme.ink900,
                        content: Text('Profile photo removed', style: AppTheme.body(size: 12, color: AppTheme.white)),
                      ),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.redMissed, width: 1),
                    ),
                    child: Text('REMOVE CURRENT PHOTO', style: AppTheme.label(size: 8.5, color: AppTheme.redMissed)),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);

    return Stack(
      children: [
        RefreshIndicator(
          color: AppTheme.greenNeon,
          backgroundColor: AppTheme.ink900,
          onRefresh: () async {
            await tele.fetchBackendData();
            await tele.fetchDeviceCallLogs();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              // Top Header Bar
              TopHeader(
                title: 'PROFILE',
                userName: tele.currentUserName,
                selectedSimIndex: tele.activeSimSlot,
              ),
              const SizedBox(height: 16),

              // Card -1: MANAGER PROFILE CARD
              NeoCard(
                backgroundColor: AppTheme.white,
                shadowColor: AppTheme.ink900,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => _showManagerPhotoPicker(context, tele),
                      child: Stack(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
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
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.cover,
                                    )
                                  : Center(
                                      child: Text(
                                        tele.currentUserName.isNotEmpty ? tele.currentUserName[0].toUpperCase() : '👨‍💼',
                                        style: AppTheme.headline(size: 22, color: AppTheme.ink900),
                                      ),
                                    ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: AppTheme.greenNeon,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.photo_camera, size: 11, color: AppTheme.ink900),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tele.currentUserName.toUpperCase(),
                            style: AppTheme.bodyBold(size: 15, color: AppTheme.ink900),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${tele.currentUserRole.toUpperCase()} · ${tele.currentUserTeam}',
                            style: AppTheme.label(size: 8.5, color: AppTheme.muted, letterSpacing: 0.12),
                          ),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () => _showManagerPhotoPicker(context, tele),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.limeYellow,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: AppTheme.ink900, width: 1),
                              ),
                              child: Text(
                                '📷 SET PROFILE PHOTO',
                                style: AppTheme.label(size: 8, color: AppTheme.ink900),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Card 0: ADMIN WEB PORTAL & USER MANAGEMENT
              NeoCard(
                backgroundColor: AppTheme.ink900,
                shadowColor: AppTheme.ink900,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('ADMIN WEB PORTAL', style: AppTheme.headline(size: 18, color: AppTheme.white)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.greenNeon,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppTheme.ink900, width: 1),
                          ),
                          child: Text('WEB APP', style: AppTheme.label(size: 8.5, color: AppTheme.ink900)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Manage telesales team, add users/callers & view cloud telemetry.', style: AppTheme.body(size: 11, color: AppTheme.lightMuted)),
                    GestureDetector(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppTheme.ink900,
                            content: Text('ℹ Admin Web Portal (http://localhost:8080) handles role provisioning.', style: AppTheme.body(size: 12, color: AppTheme.limeYellow)),
                          ),
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.greenNeon,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.ink900, width: 1.2),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.language_rounded, size: 16, color: AppTheme.ink900),
                            const SizedBox(width: 6),
                            Text(
                              'OPEN WEB ADMIN PORTAL',
                              style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Card 1: Employee detail
              GestureDetector(
                onTap: widget.onNavigateToBoard,
                child: NeoCard(
                  backgroundColor: AppTheme.white,
                  shadowColor: AppTheme.ink900,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Employee detail', style: AppTheme.bodyBold(size: 15, color: AppTheme.ink900)),
                          const SizedBox(height: 2),
                          Text('Per-caller breakdown via leaderboard', style: AppTheme.body(size: 12, color: AppTheme.muted)),
                        ],
                      ),
                      const Icon(Icons.arrow_forward, size: 18, color: AppTheme.ink900),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Card 2: Performance Report with Date Range Filter
              NeoCard(
                backgroundColor: AppTheme.ink900,
                shadowColor: AppTheme.ink900,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _reportDateRange != null
                                  ? 'Report · ${DateFormat('d MMM').format(_reportDateRange!.start)} - ${DateFormat('d MMM').format(_reportDateRange!.end)}'
                                  : 'Activity Report · ${DateFormat('d MMM yyyy').format(DateTime.now())}',
                              style: AppTheme.headline(size: 16, color: AppTheme.white),
                            ),
                            const SizedBox(height: 3),
                            Text('Call logs, outcomes & team performance', style: AppTheme.body(size: 11, color: AppTheme.lightMuted)),
                          ],
                        ),
                        GestureDetector(
                          onTap: () => _selectReportDateRange(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.paper,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.date_range_rounded, size: 14, color: AppTheme.ink900),
                                const SizedBox(width: 4),
                                Text('DATE RANGE', style: AppTheme.label(size: 8.5, color: AppTheme.ink900)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: _triggerExport,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.limeYellow,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppTheme.ink900, width: 1.2),
                          boxShadow: AppTheme.neoShadowSm(color: AppTheme.limeYellow),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.download_rounded, size: 16, color: AppTheme.ink900),
                            const SizedBox(width: 6),
                            Text(
                              _isReportSent ? '✓ EXPORTED & DOWNLOADED' : 'DOWNLOAD REPORT (XLSX / CSV)',
                              style: AppTheme.label(size: 10.5, color: AppTheme.ink900, letterSpacing: 0.12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Card 3: RECORDING STORAGE
              Builder(
                builder: (ctx) {
                  final count = tele.recordings.length;
                  final usedMb = count * 1.8;
                  final usedGb = (usedMb / 1024).clamp(0.02, 5.0);
                  final freeGb = (5.0 - usedGb).clamp(0.0, 5.0);

                  return NeoCard(
                    backgroundColor: AppTheme.white,
                    shadowColor: AppTheme.ink900,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'RECORDING STORAGE',
                              style: AppTheme.label(size: 9, color: AppTheme.ink900, letterSpacing: 0.18),
                            ),
                            Text(
                              '$count SAVED AUDIOS',
                              style: AppTheme.mono(size: 9, color: AppTheme.greenDark, weight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppTheme.paper,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: AppTheme.ink900, width: 0.8),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: (usedGb / 5.0).clamp(0.05, 1.0),
                              child: Container(color: AppTheme.greenNeon),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${usedGb.toStringAsFixed(2)} GB used · ${freeGb.toStringAsFixed(2)} GB free of 5 GB storage',
                          style: AppTheme.mono(size: 10, color: AppTheme.muted),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Hardware recording audio saved locally and backed up to cloud vault.',
                          style: AppTheme.body(size: 9.5, color: AppTheme.muted),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              // Card 4: Sync device call log
              NeoCard(
                backgroundColor: AppTheme.white,
                shadowColor: AppTheme.ink900,
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sync device call log', style: AppTheme.bodyBold(size: 15, color: AppTheme.ink900)),
                        const SizedBox(height: 2),
                        Text(
                          'Last synced ${DateFormat("h:mm a").format(DateTime.now())}',
                          style: AppTheme.body(size: 12, color: AppTheme.muted),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppTheme.greenNeon, shape: BoxShape.rectangle)),
                        const SizedBox(width: 6),
                        Text('• LIVE', style: AppTheme.label(size: 9.5, color: AppTheme.greenNeon, letterSpacing: 0.1)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Card 5: Centered Compact Logout Button
              Center(
                child: SizedBox(
                  width: 200,
                  child: GestureDetector(
                    onTap: () => _showMoreLogoutConfirmDialog(context, tele),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppTheme.redMissed, width: 1.5),
                        boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.logout_rounded, color: AppTheme.redMissed, size: 16),
                          const SizedBox(width: 6),
                          Text('LOGOUT', style: AppTheme.label(size: 11, color: AppTheme.redMissed, letterSpacing: 0.12)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

        // Bottom Notification Banner matching Screenshot 3
        if (_showBanner)
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.ink900,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.greenNeon, width: 1.5),
                boxShadow: AppTheme.neoShadow(color: AppTheme.ink900, offset: 4),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '✓  SUCCESSFULLY EXPORTED — REPORT SENT',
                    style: AppTheme.label(
                      size: 10,
                      color: AppTheme.limeYellow,
                      letterSpacing: 0.14,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _showMoreLogoutConfirmDialog(BuildContext context, TeleProvider tele) {
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
                color: AppTheme.redMissed,
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
              backgroundColor: AppTheme.redMissed,
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
            child: Text('YES, LOGOUT', style: AppTheme.label(size: 11, color: AppTheme.white)),
          ),
        ],
      ),
    );
  }
}
