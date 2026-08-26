import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../widgets/neo_button.dart';
import '../../widgets/top_header.dart';
import '../../providers/tele_provider.dart';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  int _selectedFilterIndex = 0; // 0 = ALL, 1 = OVER 5M, 2 = UNDER 5M
  final String _selectedStaff = 'ALL STAFF';
  final Map<String, int> _ratings = {};

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);

    final callerName = tele.callerName.isNotEmpty ? tele.callerName.toUpperCase() : 'RASMI DESAI';

    final List<Map<String, dynamic>> dynamicRecordings = [];

    for (var r in tele.recordings) {
      dynamicRecordings.add({
        'id': r.id,
        'callerName': r.agentName,
        'contactName': r.clientName,
        'timeStr': 'Recorded · ${r.duration.inMinutes}m ${r.duration.inSeconds % 60}s',
        'quote': r.note.isNotEmpty ? '"${r.note}"' : '"Voice call recording logged."',
        'isPlaying': r.isPlaying,
        'progress': r.progress,
      });
    }

    final totalCount = dynamicRecordings.length;

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
            TopHeader(
              title: 'RECORDINGS',
              userName: callerName,
              selectedSimIndex: 1,
            ),
            const SizedBox(height: 14),

            // ALL STAFF Dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppTheme.ink900, width: 1.5),
                boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _selectedStaff,
                    style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.14),
                  ),
                  const Icon(Icons.keyboard_arrow_down, size: 20, color: AppTheme.ink900),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Filter Tabs (ALL, OVER 5M, UNDER 5M)
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AppTheme.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppTheme.ink900, width: 1.2),
                    ),
                    child: Row(
                      children: [
                        _buildFilterTab('ALL · $totalCount', 0),
                        _buildFilterTab('OVER 5M', 1),
                        _buildFilterTab('UNDER 5M', 2),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Recordings List
            if (dynamicRecordings.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.mic_none, size: 44, color: AppTheme.muted),
                      const SizedBox(height: 10),
                      Text('NO RECORDINGS YET', style: AppTheme.headline(size: 18)),
                      const SizedBox(height: 4),
                      Text(
                        'Recorded calls will appear here automatically.',
                        style: AppTheme.body(size: 12, color: AppTheme.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: dynamicRecordings.length,
                separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                itemBuilder: (ctx, i) {
                  final rec = dynamicRecordings[i];
                  final id = rec['id'] as String;
                  final caller = rec['callerName'] as String;
                  final contact = rec['contactName'] as String;
                  final timeStr = rec['timeStr'] as String;
                  final quote = rec['quote'] as String;
                  final isPlaying = rec['isPlaying'] as bool? ?? false;
                  final progress = rec['progress'] as double? ?? 0.0;
                  final rating = _ratings[id] ?? 0;

                  return NeoCard(
                    backgroundColor: AppTheme.white,
                    shadowColor: AppTheme.ink900,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header: Caller -> Contact
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '$caller → ',
                                  style: AppTheme.label(size: 11, color: AppTheme.greenDark),
                                ),
                                Text(
                                  contact,
                                  style: AppTheme.bodyBold(size: 14, color: AppTheme.ink900),
                                ),
                              ],
                            ),
                            GestureDetector(
                              onTap: () => tele.toggleRecordingPlayback(id),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: isPlaying ? AppTheme.greenNeon : AppTheme.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppTheme.ink900, width: 1.2),
                                ),
                                child: Icon(
                                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  size: 20,
                                  color: AppTheme.ink900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),

                        // Time & Duration
                        Text(
                          timeStr,
                          style: AppTheme.mono(size: 10, color: AppTheme.muted),
                        ),
                        const SizedBox(height: 8),

                        // Audio Progress Line
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            height: 4,
                            color: AppTheme.paper,
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: isPlaying ? progress : 0.0,
                              child: Container(color: AppTheme.greenNeon),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Quote Block
                        Text(
                          quote,
                          style: AppTheme.italicSerif(size: 12.5, color: AppTheme.ink900),
                        ),
                        const SizedBox(height: 12),

                        // Call Quality Rating & Save Button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text('Call Quality:', style: AppTheme.label(size: 9, color: AppTheme.muted)),
                                const SizedBox(width: 6),
                                Row(
                                  children: List.generate(5, (starIdx) {
                                    final isStarred = starIdx < rating;
                                    return GestureDetector(
                                      onTap: () => setState(() => _ratings[id] = starIdx + 1),
                                      child: Icon(
                                        isStarred ? Icons.star : Icons.star_border,
                                        size: 16,
                                        color: isStarred ? AppTheme.orangePill : AppTheme.muted,
                                      ),
                                    );
                                  }),
                                ),
                              ],
                            ),
                            NeoButton.pill(
                              backgroundColor: AppTheme.ink900,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: AppTheme.ink900,
                                    content: Text('Recording feedback saved.', style: AppTheme.bodyBold(size: 12, color: AppTheme.limeYellow)),
                                  ),
                                );
                              },
                              child: Text(
                                'SAVE',
                                style: AppTheme.label(size: 8.5, color: AppTheme.limeYellow),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTab(String label, int index) {
    final isSelected = _selectedFilterIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedFilterIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.ink900 : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            child: Text(
              label,
              style: AppTheme.label(
                size: 8.5,
                color: isSelected ? AppTheme.limeYellow : AppTheme.ink900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
