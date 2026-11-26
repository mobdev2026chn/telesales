import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'neo_card.dart';

class AutoRecordToggleCard extends StatelessWidget {
  final bool isEnabled;
  final VoidCallback onToggle;

  const AutoRecordToggleCard({
    super.key,
    required this.isEnabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return NeoCard(
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
                  style: AppTheme.label(
                    size: 9,
                    color: AppTheme.ink900,
                    letterSpacing: 0.1,
                  ),
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
            value: isEnabled,
            activeThumbColor: AppTheme.greenNeon,
            activeTrackColor: AppTheme.ink900,
            onChanged: (_) => onToggle(),
          ),
        ],
      ),
    );
  }
}
