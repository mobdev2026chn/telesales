import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import 'neo_button.dart';
import '../providers/tele_provider.dart';

class AdvancedFilterSheet extends StatefulWidget {
  const AdvancedFilterSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const AdvancedFilterSheet(),
    );
  }

  @override
  State<AdvancedFilterSheet> createState() => _AdvancedFilterSheetState();
}

class _AdvancedFilterSheetState extends State<AdvancedFilterSheet> {
  int _qualityIndex = 0; // 0 = ANY, 1 = SHORT (<2M), 2 = MEDIUM (2-5M), 3 = LONG (>5M), 4 = UNANSWERED
  int _frequencyIndex = 0; // 0 = ALL, 1 = ONCE, 2 = REPEATED
  int _timeOfDayIndex = 0; // 0 = ANY, 1 = MORNING, 2 = AFTERNOON, 3 = EVENING

  final List<String> _qualityOpts = [
    'ANY QUALITY',
    'SHORT (< 2 MINS)',
    'MEDIUM (2 - 5 MINS)',
    'LONG (> 5 MINS)',
    'UNANSWERED / MISSED'
  ];
  final List<String> _frequencyOpts = ['ALL', 'ONCE', 'REPEATED'];
  final List<String> _timeOfDayOpts = ['ANY', 'MORNING', 'AFTERNOON', 'EVENING'];

  @override
  void initState() {
    super.initState();
    final tele = Provider.of<TeleProvider>(context, listen: false);
    _qualityIndex = tele.callQualityFilter;
  }

  void _reset() {
    setState(() {
      _qualityIndex = 0;
      _frequencyIndex = 0;
      _timeOfDayIndex = 0;
    });
    final tele = Provider.of<TeleProvider>(context, listen: false);
    tele.setCallQualityFilter(0);
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);
    final allLogs = tele.simTrackedCallLogs;
    
    // Compute matching count
    int matchingCount = allLogs.length;
    if (_qualityIndex == 1) {
      matchingCount = allLogs.where((c) => c.duration.inSeconds > 0 && c.duration.inSeconds < 120).length;
    } else if (_qualityIndex == 2) {
      matchingCount = allLogs.where((c) => c.duration.inSeconds >= 120 && c.duration.inSeconds <= 300).length;
    } else if (_qualityIndex == 3) {
      matchingCount = allLogs.where((c) => c.duration.inSeconds > 300).length;
    } else if (_qualityIndex == 4) {
      matchingCount = allLogs.where((c) => c.duration.inSeconds == 0 || c.type.name == 'missed').length;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header: ADVANCED FILTER. & Close
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text('CALL QUALITY FILTER', style: AppTheme.headline(size: 22, color: AppTheme.ink900)),
                  Text('.', style: AppTheme.headline(size: 22, color: AppTheme.greenNeon)),
                ],
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.ink900, width: 1.2),
                  ),
                  child: const Icon(Icons.close, size: 16, color: AppTheme.ink900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // QUALITY OF CALLS Section
          Text('QUALITY OF CALLS (DURATION TRACKING)', style: AppTheme.label(size: 9, color: AppTheme.ink900, letterSpacing: 0.18)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_qualityOpts.length, (index) {
              final isSel = _qualityIndex == index;
              return GestureDetector(
                onTap: () => setState(() => _qualityIndex = index),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSel ? AppTheme.ink900 : AppTheme.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppTheme.ink900, width: 1.2),
                  ),
                  child: Text(
                    _qualityOpts[index],
                    style: AppTheme.label(
                      size: 9,
                      color: isSel ? AppTheme.limeYellow : AppTheme.ink900,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),

          // FREQUENCY Section
          Text('CALL FREQUENCY', style: AppTheme.label(size: 9, color: AppTheme.ink900, letterSpacing: 0.18)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_frequencyOpts.length, (index) {
              final isSel = _frequencyIndex == index;
              return GestureDetector(
                onTap: () => setState(() => _frequencyIndex = index),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSel ? AppTheme.ink900 : AppTheme.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppTheme.ink900, width: 1.2),
                  ),
                  child: Text(
                    _frequencyOpts[index],
                    style: AppTheme.label(
                      size: 9,
                      color: isSel ? AppTheme.limeYellow : AppTheme.ink900,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),

          // TIME OF DAY Section
          Text('TIME OF DAY', style: AppTheme.label(size: 9, color: AppTheme.ink900, letterSpacing: 0.18)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_timeOfDayOpts.length, (index) {
              final isSel = _timeOfDayIndex == index;
              return GestureDetector(
                onTap: () => setState(() => _timeOfDayIndex = index),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSel ? AppTheme.ink900 : AppTheme.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppTheme.ink900, width: 1.2),
                  ),
                  child: Text(
                    _timeOfDayOpts[index],
                    style: AppTheme.label(
                      size: 9,
                      color: isSel ? AppTheme.limeYellow : AppTheme.ink900,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),

          // Action Buttons (RESET | APPLY FILTERS)
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _reset,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppTheme.ink900, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        'RESET',
                        style: AppTheme.label(size: 10, color: AppTheme.ink900),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: NeoButton(
                  backgroundColor: AppTheme.ink900,
                  shadowColor: AppTheme.greenNeon,
                  onTap: () {
                    tele.setCallQualityFilter(_qualityIndex);
                    Navigator.of(context).pop();
                  },
                  child: Center(
                    child: Text(
                      'APPLY · SHOW $matchingCount CALLS →',
                      style: AppTheme.label(size: 10.5, color: AppTheme.limeYellow, letterSpacing: 0.12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

