import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'neo_button.dart';

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
  int _durationIndex = 0; // 0 = ANY, 1 = UNDER 2M, 2 = OVER 5M, 3 = NOT CONNECTED
  int _frequencyIndex = 0; // 0 = ALL, 1 = ONCE, 2 = REPEATED
  int _timeOfDayIndex = 0; // 0 = ANY, 1 = MORNING, 2 = AFTERNOON, 3 = EVENING

  final List<String> _durationOpts = ['ANY', 'UNDER 2M', 'OVER 5M', 'NOT CONNECTED'];
  final List<String> _frequencyOpts = ['ALL', 'ONCE', 'REPEATED'];
  final List<String> _timeOfDayOpts = ['ANY', 'MORNING', 'AFTERNOON', 'EVENING'];

  void _reset() {
    setState(() {
      _durationIndex = 0;
      _frequencyIndex = 0;
      _timeOfDayIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                  Text('ADVANCED FILTER', style: AppTheme.headline(size: 24, color: AppTheme.ink900)),
                  Text('.', style: AppTheme.headline(size: 24, color: AppTheme.greenNeon)),
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

          // DURATION Section
          Text('DURATION', style: AppTheme.label(size: 9, color: AppTheme.ink900, letterSpacing: 0.18)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_durationOpts.length, (index) {
              final isSel = _durationIndex == index;
              return GestureDetector(
                onTap: () => setState(() => _durationIndex = index),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSel ? AppTheme.ink900 : AppTheme.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppTheme.ink900, width: 1.2),
                  ),
                  child: Text(
                    _durationOpts[index],
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
          Text('FREQUENCY', style: AppTheme.label(size: 9, color: AppTheme.ink900, letterSpacing: 0.18)),
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

          // Action Buttons (RESET | SHOW 4 CALLS ->)
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
                  onTap: () => Navigator.of(context).pop(),
                  child: Center(
                    child: Text(
                      'SHOW 4 CALLS →',
                      style: AppTheme.label(size: 11, color: AppTheme.limeYellow, letterSpacing: 0.12),
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
