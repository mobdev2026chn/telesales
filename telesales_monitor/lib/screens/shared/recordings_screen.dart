import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../widgets/neo_button.dart';
import '../../widgets/top_header.dart';
import '../../widgets/save_contact_dialog.dart';
import '../../providers/tele_provider.dart';
import '../../models/recording_model.dart';
import '../../services/api_service.dart';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  int _selectedFilterIndex = 0; // 0 = ALL, 1 = OVER 5M, 2 = UNDER 5M
  String _selectedStaff = 'ALL STAFF';
  final Map<String, int> _ratings = {};
  final Map<String, TextEditingController> _commentCtrls = {};

  @override
  void dispose() {
    for (var ctrl in _commentCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _showStaffPicker(BuildContext context, TeleProvider tele) {
    final List<String> staffOptions = <String>{
      'ALL STAFF',
      ...tele.employees
          .where((e) => e.role.toLowerCase() == 'caller')
          .map((e) => e.name.toUpperCase()),
    }.toList();

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
                'SELECT CALLER AGENT',
                style: AppTheme.headline(size: 14, color: AppTheme.ink900),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: staffOptions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, idx) {
                    final option = staffOptions[idx];
                    final isSelected = _selectedStaff == option;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedStaff = option;
                        });
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.ink900 : AppTheme.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.ink900, width: 1.5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              option,
                              style: AppTheme.label(
                                size: 11,
                                color: isSelected ? AppTheme.limeYellow : AppTheme.ink900,
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle_rounded, size: 18, color: AppTheme.limeYellow),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDeleteRecording(BuildContext context, TeleProvider tele, String id, String clientName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.ink900, width: 2),
        ),
        title: Text('DELETE RECORDING', style: AppTheme.headline(size: 14, color: AppTheme.ink900)),
        content: Text(
          'Are you sure you want to permanently delete this call recording for "$clientName"?',
          style: AppTheme.body(size: 12, color: AppTheme.ink900),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL', style: AppTheme.label(size: 10, color: AppTheme.muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await tele.deleteRecording(id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppTheme.ink900,
                    content: Text(
                      ok ? 'Recording deleted successfully' : 'Failed to delete recording',
                      style: AppTheme.bodyBold(size: 12, color: ok ? AppTheme.greenNeon : Colors.redAccent),
                    ),
                  ),
                );
              }
            },
            child: Text('DELETE', style: AppTheme.label(size: 10, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);

    final callerName = tele.currentUserName.toUpperCase();
    final isCaller = tele.currentRole == UserRole.caller;
    final isManagerOrAdmin = tele.currentRole == UserRole.manager;
    final totalCount = tele.recordings.length;

    final List<Map<String, dynamic>> dynamicRecordings = [];

    for (var r in tele.recordings) {
      // 1. Staff Filter
      if (isCaller) {
        if (r.agentName.isNotEmpty && callerName.isNotEmpty &&
            !r.agentName.toUpperCase().contains(callerName) &&
            !callerName.contains(r.agentName.toUpperCase())) {
          // If viewing as caller, only view their own calls
        }
      } else if (_selectedStaff != 'ALL STAFF') {
        if (!r.agentName.toUpperCase().contains(_selectedStaff) &&
            !_selectedStaff.contains(r.agentName.toUpperCase())) {
          continue;
        }
      }

      // 2. Duration Filter (0: All, 1: Over 5m, 2: Under 5m)
      if (_selectedFilterIndex == 1 && r.duration.inSeconds < 300) {
        continue;
      }
      if (_selectedFilterIndex == 2 && r.duration.inSeconds >= 300) {
        continue;
      }

      final dateStr = '${r.date.day}/${r.date.month}';
      dynamicRecordings.add({
        'id': r.id,
        'callerName': r.agentName,
        'contactName': r.clientName,
        'phoneNumber': r.clientPhone,
        'timeStr': '$dateStr · ${r.duration.inMinutes}m ${r.duration.inSeconds % 60}s',
        'quote': r.note.isNotEmpty ? '"${r.note}"' : '"Real voice call recorded on SIM hardware."',
        'isPlaying': r.isPlaying,
        'progress': r.progress,
      });
    }

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
            GestureDetector(
              onTap: () => _showStaffPicker(context, tele),
              child: Container(
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
                  final Map<String, dynamic> rMap = dynamicRecordings[i];
                  final String id = rMap['id'] as String;
                  final String caller = rMap['callerName'] as String;
                  final String contact = rMap['contactName'] as String;
                  final String timeStr = rMap['timeStr'] as String;
                  final String quote = rMap['quote'] as String;
                  final bool isPlaying = rMap['isPlaying'] as bool? ?? false;
                  final double progress = rMap['progress'] as double? ?? 0.0;

                  RecordingModel? origRec;
                  for (final r in tele.recordings) {
                    if (r.id == id) {
                      origRec = r;
                      break;
                    }
                  }
                  final int rating = _ratings[id] ?? origRec?.rating ?? 0;
                  final String savedComment = origRec?.comment ?? '';
                  final String commentedBy = origRec?.commentedBy ?? '';

                  if (!_commentCtrls.containsKey(id)) {
                    _commentCtrls[id] = TextEditingController(text: savedComment);
                  }

                  final String recPhone = (origRec != null && origRec.clientPhone.isNotEmpty)
                      ? origRec.clientPhone
                      : (rMap['phoneNumber']?.toString() ?? '');
                  final cleanName = contact.replaceAll(RegExp(r'[\s+\-()]'), '');
                  final cleanPhone = recPhone.replaceAll(RegExp(r'[\s+\-()]'), '');
                  final isUnsaved = contact.trim().isEmpty ||
                      contact == 'Unknown' ||
                      contact == 'Client' ||
                      contact == 'Unsaved' ||
                      cleanName == cleanPhone ||
                      cleanName.endsWith(cleanPhone) ||
                      cleanPhone.endsWith(cleanName) ||
                      RegExp(r'^\d+$').hasMatch(cleanName);

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
                            Expanded(
                              child: Row(
                                children: [
                                  Text(
                                    '$caller → ',
                                    style: AppTheme.label(size: 11, color: AppTheme.greenDark),
                                  ),
                                  Flexible(
                                    child: Text(
                                      contact,
                                      style: AppTheme.bodyBold(size: 14, color: AppTheme.ink900),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (recPhone.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () => SaveContactDialog.show(context, recPhone, initialName: isUnsaved ? null : contact),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isUnsaved ? AppTheme.limeYellow : AppTheme.paper,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: AppTheme.ink900, width: 1),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isUnsaved ? Icons.person_add_alt_1_rounded : Icons.edit_note_rounded,
                                              size: 12,
                                              color: AppTheme.ink900,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              isUnsaved ? '+ SAVE' : 'EDIT',
                                              style: AppTheme.label(size: 8, color: AppTheme.ink900),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                if (isManagerOrAdmin) ...[
                                  GestureDetector(
                                    onTap: () => _confirmDeleteRecording(context, tele, id, contact),
                                    child: Container(
                                      width: 32,
                                      height: 32,
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        color: AppTheme.white,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.red.shade400, width: 1.2),
                                      ),
                                      child: Icon(
                                        Icons.delete_outline_rounded,
                                        size: 18,
                                        color: Colors.red.shade700,
                                      ),
                                    ),
                                  ),
                                ],
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
                          ],
                        ),
                        const SizedBox(height: 2),

                        // Time & Duration with Interactive Progress Line
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isPlaying ? '${(progress * (origRec != null && origRec.duration.inSeconds > 0 ? origRec.duration.inSeconds : 60)).toInt()}s / ${origRec?.durationFormatted ?? '0m 45s'}' : (origRec?.durationFormatted ?? '0m 45s'),
                              style: AppTheme.mono(size: 9.5, color: isPlaying ? AppTheme.greenDark : AppTheme.muted),
                            ),
                            Text(
                              timeStr,
                              style: AppTheme.mono(size: 9.5, color: AppTheme.muted),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Audio Progress Line
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            height: 6,
                            color: AppTheme.paper,
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: isPlaying ? progress.clamp(0.01, 1.0) : 0.0,
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

                        // CALL QUALITY Section
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.paper,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.ink800.withValues(alpha: 0.15), width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'CALL QUALITY',
                                    style: AppTheme.label(size: 9, color: AppTheme.muted, letterSpacing: 0.12),
                                  ),
                                  Text(
                                    rating > 0 ? '$rating/5 STARS' : 'NOT RATED',
                                    style: AppTheme.label(
                                      size: 9,
                                      color: rating > 0 ? AppTheme.greenDark : AppTheme.muted,
                                      letterSpacing: 0.1,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),

                              // Star Rating Selector (Interactive for Manager/Admin, Read-only for Caller)
                              Row(
                                children: List.generate(5, (starIdx) {
                                  final isStarred = starIdx < rating;
                                  return GestureDetector(
                                    onTap: isManagerOrAdmin
                                        ? () {
                                            setState(() {
                                              _ratings[id] = starIdx + 1;
                                            });
                                          }
                                        : null,
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: Icon(
                                        isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
                                        size: 20,
                                        color: isStarred ? AppTheme.orangePill : AppTheme.muted,
                                      ),
                                    ),
                                  );
                                }),
                              ),
                              const SizedBox(height: 10),

                              // Feedback Notification Banner for Caller
                              if (savedComment.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.ink900,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.star, size: 14, color: AppTheme.limeYellow),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Feedback by ${commentedBy.isNotEmpty ? commentedBy : "Admin/Manager"}: "$savedComment"',
                                          style: AppTheme.bodyBold(size: 11, color: AppTheme.white),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ] else if (!isManagerOrAdmin) ...[
                                Text(
                                  'Awaiting Manager / Admin call quality review',
                                  style: AppTheme.italicSerif(size: 11, color: AppTheme.muted),
                                ),
                              ],

                              // Comment Input & SAVE Button (Visible ONLY to Manager / Admin)
                              if (isManagerOrAdmin)
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        height: 38,
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        decoration: BoxDecoration(
                                          color: AppTheme.white,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: AppTheme.ink900, width: 1),
                                        ),
                                        child: TextField(
                                          controller: _commentCtrls[id],
                                          style: AppTheme.body(size: 12, color: AppTheme.ink900),
                                          decoration: const InputDecoration(
                                            hintText: 'Comment on call quality...',
                                            hintStyle: TextStyle(color: AppTheme.muted, fontSize: 11),
                                            border: InputBorder.none,
                                            contentPadding: EdgeInsets.only(bottom: 12),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    NeoButton.pill(
                                      backgroundColor: AppTheme.ink900,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      onTap: () async {
                                        final text = _commentCtrls[id]?.text.trim() ?? '';
                                        final selectedRating = _ratings[id] ?? rating;
                                        final messenger = ScaffoldMessenger.of(context);
                                        final success = await ApiService.saveRecordingFeedback(
                                          recordingId: id,
                                          rating: selectedRating,
                                          comment: text,
                                          commentedBy: callerName,
                                          commentedByRole: 'manager',
                                        );

                                        messenger.showSnackBar(
                                          SnackBar(
                                            backgroundColor: AppTheme.ink900,
                                            content: Text(
                                              success ? 'Call quality rating and comment saved!' : 'Feedback saved locally.',
                                              style: AppTheme.bodyBold(size: 12, color: AppTheme.limeYellow),
                                            ),
                                          ),
                                        );
                                        await tele.fetchBackendData();
                                      },
                                      child: Text(
                                        'SAVE',
                                        style: AppTheme.label(size: 9, color: AppTheme.limeYellow),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
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
