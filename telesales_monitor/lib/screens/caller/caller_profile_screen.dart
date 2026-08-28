import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../widgets/neo_button.dart';
import '../../providers/tele_provider.dart';

class CallerProfileScreen extends StatefulWidget {
  const CallerProfileScreen({super.key});

  @override
  State<CallerProfileScreen> createState() => _CallerProfileScreenState();
}

class _CallerProfileScreenState extends State<CallerProfileScreen> {
  String _selectedAvatar = '👨‍💼';
  final List<String> _avatarOptions = ['👨‍💼', '👩‍💼', '🧑‍💻', '👔', '🎧', '⚡', '🌟', '🎯'];

  void _showAvatarPicker(BuildContext context, TeleProvider tele) {
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

              // Action Buttons: Gallery & Camera
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
              const SizedBox(height: 16),

              if (tele.profilePhotoBase64.isNotEmpty || tele.profilePhotoPath.isNotEmpty) ...[
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
                const SizedBox(height: 16),
              ],

              Text(
                'OR CHOOSE AVATAR EMOJI',
                style: AppTheme.label(size: 8.5, color: AppTheme.muted, letterSpacing: 0.14),
              ),
              const SizedBox(height: 10),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: _avatarOptions.length,
                itemBuilder: (ctx, idx) {
                  final av = _avatarOptions[idx];
                  final isSel = _selectedAvatar == av && tele.profilePhotoBase64.isEmpty;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedAvatar = av);
                      tele.clearProfilePhoto();
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSel ? AppTheme.limeYellow : AppTheme.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.ink900, width: isSel ? 2.5 : 1.5),
                        boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                      ),
                      child: Center(
                        child: Text(av, style: const TextStyle(fontSize: 32)),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditCallerNameDialog(BuildContext context, TeleProvider tele) {
    final nameCtrl = TextEditingController(text: tele.callerName);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              decoration: BoxDecoration(
                color: AppTheme.paper,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: AppTheme.ink900, width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'SET CALLER NAME',
                        style: AppTheme.label(size: 11, color: AppTheme.ink900, letterSpacing: 0.16),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppTheme.ink900),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your preferred caller display name for admin leaderboard & call sync.',
                    style: AppTheme.body(size: 12, color: AppTheme.muted),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.ink900, width: 1.2),
                    ),
                    child: TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      style: AppTheme.bodyBold(size: 14),
                      decoration: const InputDecoration(
                        hintText: 'e.g. Sales Agent 1',
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.person_outline, color: AppTheme.ink900),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  NeoButton.accent(
                    onTap: () {
                      final newName = nameCtrl.text.trim();
                      if (newName.isNotEmpty) {
                        tele.setCallerName(newName);
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppTheme.ink900,
                            content: Text(
                              'Caller name updated to "$newName"',
                              style: AppTheme.bodyBold(size: 12, color: AppTheme.greenNeon),
                            ),
                          ),
                        );
                      }
                    },
                    child: Center(
                      child: Text(
                        'SAVE CALLER NAME →',
                        style: AppTheme.label(size: 11, color: AppTheme.ink900, letterSpacing: 0.12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);

    final callerName = tele.callerName.isNotEmpty ? tele.callerName : 'Device Caller';
    final phoneStr = tele.verifiedTrackingNumber.isNotEmpty ? tele.verifiedTrackingNumber : '+91 98250 12340';
    final total = tele.trackedTotalCalls;
    final connected = tele.trackedConnectedCalls;
    final talkTimeStr = tele.trackedTalkTimeFormatted;

    return RefreshIndicator(
      color: AppTheme.greenNeon,
      backgroundColor: AppTheme.ink900,
      onRefresh: () async {
        await tele.fetchBackendData();
        await tele.fetchDeviceCallLogs();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Header Card with Avatar
            NeoCard(
              backgroundColor: AppTheme.ink900,
              shadowColor: AppTheme.ink900,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'DEVICE CALLER PROFILE',
                        style: AppTheme.label(size: 9, color: AppTheme.limeYellow, letterSpacing: 0.18),
                      ),
                      GestureDetector(
                        onTap: () => _showEditCallerNameDialog(context, tele),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.greenNeon,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppTheme.ink900, width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.edit, size: 11, color: AppTheme.ink900),
                              const SizedBox(width: 4),
                              Text(
                                'EDIT NAME',
                                style: AppTheme.label(size: 8, color: AppTheme.ink900),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      // Avatar Photo with Edit Button
                      GestureDetector(
                        onTap: () => _showAvatarPicker(context, tele),
                        child: Stack(
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: AppTheme.paper,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppTheme.limeYellow, width: 2),
                                boxShadow: AppTheme.neoShadowSm(color: AppTheme.limeYellow),
                              ),
                              child: ClipOval(
                                child: tele.profilePhotoBase64.isNotEmpty
                                    ? Image.memory(
                                        base64Decode(tele.profilePhotoBase64),
                                        width: 64,
                                        height: 64,
                                        fit: BoxFit.cover,
                                      )
                                    : Center(
                                        child: Text(_selectedAvatar, style: const TextStyle(fontSize: 30)),
                                      ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: AppTheme.greenNeon,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.photo_camera, size: 13, color: AppTheme.ink900),
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
                              callerName,
                              style: AppTheme.headline(size: 22, color: AppTheme.paper),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$phoneStr · ${tele.activeSimLabel}',
                              style: AppTheme.body(size: 11, color: AppTheme.lightMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

          // Auto-Record Toggle Card
          NeoCard(
            backgroundColor: AppTheme.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.paper,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.ink900, width: 1.2),
                  ),
                  child: const Icon(Icons.mic, color: AppTheme.greenDark, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AUTO-RECORD ALL CALLS',
                        style: AppTheme.label(size: 9, color: AppTheme.ink900, letterSpacing: 0.1),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Auto-records audio during active ongoing calls',
                        style: AppTheme.body(size: 11, color: AppTheme.muted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: tele.autoRecordEnabled,
                  activeThumbColor: AppTheme.greenNeon,
                  activeTrackColor: AppTheme.ink900,
                  onChanged: (_) => tele.toggleAutoRecord(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Live Metrics Card
          NeoCard(
            backgroundColor: AppTheme.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LIVE PERFORMANCE SUMMARY',
                  style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.18),
                ),
                const SizedBox(height: 16),
                _TargetBar(
                  label: 'Total calls ($total logged)',
                  progress: total > 0 ? (total / 50).clamp(0.05, 1.0) : 0.05,
                  color: AppTheme.greenNeon,
                ),
                const SizedBox(height: 14),
                _TargetBar(
                  label: 'Connected ($connected calls)',
                  progress: total > 0 ? (connected / total).clamp(0.05, 1.0) : 0.05,
                  color: AppTheme.limeYellow,
                ),
                const SizedBox(height: 14),
                _TargetBar(
                  label: 'Talk time ($talkTimeStr)',
                  progress: total > 0 ? 0.75 : 0.05,
                  color: AppTheme.greenGrass,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  }
}

class _TargetBar extends StatelessWidget {
  final String label;
  final double progress;
  final Color color;

  const _TargetBar({
    required this.label,
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTheme.bodyBold(size: 12)),
            Text('${(progress * 100).toInt()}%', style: AppTheme.mono(size: 11, color: AppTheme.muted)),
          ],
        ),
        const SizedBox(height: 6),
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
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(color: color),
            ),
          ),
        ),
      ],
    );
  }
}
