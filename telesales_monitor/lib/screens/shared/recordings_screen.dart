import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../widgets/neo_button.dart';
import '../../providers/tele_provider.dart';

class RecordingsScreen extends StatelessWidget {
  const RecordingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);
    final currentDateStr = DateFormat('d MMM yyyy').format(DateTime.now()).toUpperCase();
    final recordings = tele.recordings;

    return RefreshIndicator(
      color: AppTheme.greenNeon,
      backgroundColor: AppTheme.ink900,
      onRefresh: () async {
        await tele.fetchBackendData();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'RECORDINGS',
                          style: AppTheme.headline(size: 30, color: AppTheme.ink900),
                        ),
                        Text(
                          '.',
                          style: AppTheme.headline(size: 30, color: AppTheme.greenNeon),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ASKEVA · TEAM VIEW · $currentDateStr',
                      style: AppTheme.mono(size: 10, color: AppTheme.muted),
                    ),
                  ],
                ),
                NeoButton.pill(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  onTap: () => tele.logout(),
                  child: Row(
                    children: [
                      Text(
                        tele.currentRole == UserRole.manager ? 'MANAGER' : 'CALLER',
                        style: AppTheme.label(size: 9, color: AppTheme.ink900, letterSpacing: 0.12),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.close, size: 12, color: AppTheme.ink900),
                    ],
                  ),
                ),
              ],
            ),
            // Live Test Recording & Status Card
            NeoCard(
              backgroundColor: tele.isCallRecordingActive ? AppTheme.ink900 : AppTheme.white,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tele.isCallRecordingActive ? AppTheme.redMissed : AppTheme.paper,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.ink900, width: 1.2),
                    ),
                    child: Icon(
                      tele.isCallRecordingActive ? Icons.mic : Icons.mic_none,
                      color: tele.isCallRecordingActive ? AppTheme.white : AppTheme.ink900,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tele.isCallRecordingActive ? '🔴 RECORDING LIVE NOW...' : 'AUTO-RECORDING ENGINE READY',
                          style: AppTheme.label(
                            size: 9,
                            color: tele.isCallRecordingActive ? AppTheme.limeYellow : AppTheme.ink900,
                            letterSpacing: 0.12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tele.isCallRecordingActive
                              ? 'Speaking on call · Audio capturing...'
                              : 'Incoming & Outgoing calls record automatically',
                          style: AppTheme.body(
                            size: 11,
                            color: tele.isCallRecordingActive ? AppTheme.lightMuted : AppTheme.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      if (tele.isCallRecordingActive) {
                        tele.stopTestRecording();
                      } else {
                        tele.startTestRecording();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: tele.isCallRecordingActive ? AppTheme.redMissed : AppTheme.greenNeon,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppTheme.ink900, width: 1),
                        boxShadow: AppTheme.neoShadowSm(),
                      ),
                      child: Text(
                        tele.isCallRecordingActive ? 'STOP & SAVE' : 'TEST RECORD',
                        style: AppTheme.label(
                          size: 9,
                          color: tele.isCallRecordingActive ? AppTheme.white : AppTheme.ink900,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Call Recordings indicator
            Row(
              children: [
                Container(width: 8, height: 8, color: AppTheme.greenNeon),
                const SizedBox(width: 8),
                Text(
                  'SAVED RECORDINGS (${recordings.length})',
                  style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.18),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Recordings List
            if (recordings.isEmpty)
              NeoCard(
                backgroundColor: AppTheme.white,
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.mic_none, size: 36, color: AppTheme.muted),
                      const SizedBox(height: 10),
                      Text(
                        'No call recordings in database yet.',
                        style: AppTheme.bodyBold(size: 14, color: AppTheme.ink900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Calls made on the device will be automatically recorded and synced here.',
                        textAlign: TextAlign.center,
                        style: AppTheme.body(size: 12, color: AppTheme.muted),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recordings.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final rec = recordings[index];

                return NeoCard(
                  backgroundColor: AppTheme.white,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${rec.callerName} → ${rec.contactName}',
                                  style: AppTheme.bodyBold(size: 15, color: AppTheme.ink900),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${rec.dateStr} · ${rec.timeStr} · ${rec.durationFormatted}',
                                  style: AppTheme.mono(size: 11, color: AppTheme.muted),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () => tele.toggleRecordingPlayback(rec.id),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppTheme.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppTheme.ink900, width: 1.5),
                                boxShadow: AppTheme.neoShadowSm(),
                              ),
                              child: Icon(
                                rec.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: AppTheme.ink900,
                                size: 22,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Audio Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppTheme.paper,
                            border: Border.all(color: AppTheme.ink900, width: 0.8),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: rec.progress.clamp(0.05, 1.0),
                            child: Container(color: AppTheme.greenNeon),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Transcript summary quote
                      Text(
                        rec.quote,
                        style: AppTheme.italicSerif(size: 13, color: AppTheme.ink700),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
