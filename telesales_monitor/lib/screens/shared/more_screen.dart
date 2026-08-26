import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../widgets/neo_button.dart';
import '../../providers/tele_provider.dart';

class MoreScreen extends StatelessWidget {
  final VoidCallback onNavigateToBoard;
  const MoreScreen({super.key, required this.onNavigateToBoard});

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);
    final currentDateStr = DateFormat('d MMM yyyy').format(DateTime.now()).toUpperCase();
    final todayShort = DateFormat('d MMM').format(DateTime.now());

    return SingleChildScrollView(
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
                        'MORE',
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
          const SizedBox(height: 16),

          // Card 1: Employee Detail
          GestureDetector(
            onTap: onNavigateToBoard,
            child: NeoCard(
              backgroundColor: AppTheme.white,
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Employee detail', style: AppTheme.bodyBold(size: 15)),
                      const SizedBox(height: 2),
                      Text('Per-caller breakdown via leaderboard', style: AppTheme.body(size: 12, color: AppTheme.muted)),
                    ],
                  ),
                  const Icon(Icons.arrow_forward, size: 20, color: AppTheme.ink900),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Card 2: Daily Report Export (Dark Card)
          NeoCard(
            backgroundColor: AppTheme.ink900,
            shadowColor: AppTheme.ink900,
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Daily report · $todayShort', style: AppTheme.headline(size: 18, color: AppTheme.white)),
                    const SizedBox(height: 2),
                    Text('Call log + lead status, XLSX & PDF', style: AppTheme.body(size: 11, color: AppTheme.lightMuted)),
                  ],
                ),
                GestureDetector(
                  onTap: () => tele.fakeExport(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.limeYellow,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppTheme.ink900, width: 1.5),
                    ),
                    child: Text(
                      tele.exportStatus == 'DOWNLOAD XLSX' ? '↓ EXPORT' : tele.exportStatus,
                      style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.1),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Card 3: Recording Storage
          NeoCard(
            backgroundColor: AppTheme.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RECORDING STORAGE',
                  style: AppTheme.label(size: 9, color: AppTheme.ink900, letterSpacing: 0.18),
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
                      widthFactor: (1.87 / 5.0).clamp(0.0, 1.0),
                      child: Container(color: AppTheme.limeYellow),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '1.87 GB used · 3.12 GB free of 5 GB',
                  style: AppTheme.mono(size: 10, color: AppTheme.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Card 4: Sync Device Call Log
          NeoCard(
            backgroundColor: AppTheme.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sync device call log', style: AppTheme.bodyBold(size: 15)),
                    const SizedBox(height: 2),
                    Text('MongoDB Database Connected', style: AppTheme.body(size: 12, color: AppTheme.muted)),
                  ],
                ),
                Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.greenNeon, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('LIVE', style: AppTheme.label(size: 10, color: AppTheme.greenDark, letterSpacing: 0.1)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
