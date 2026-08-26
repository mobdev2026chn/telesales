import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../widgets/top_header.dart';

class MoreScreen extends StatefulWidget {
  final VoidCallback onNavigateToBoard;
  const MoreScreen({super.key, required this.onNavigateToBoard});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  bool _isReportSent = false;
  bool _showBanner = false;

  void _triggerExport() {
    setState(() {
      _isReportSent = true;
      _showBanner = true;
    });

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _showBanner = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Header Bar
              const TopHeader(
                title: 'MORE',
                userName: 'RASMI DESAI',
                selectedSimIndex: 1,
              ),
              const SizedBox(height: 16),

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

              // Card 2: Daily report · 24 Aug (Dark Card)
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
                        Text('Daily report · 24 Aug', style: AppTheme.headline(size: 18, color: AppTheme.white)),
                        const SizedBox(height: 3),
                        Text('Call log + lead status, XLSX & PDF', style: AppTheme.body(size: 11, color: AppTheme.lightMuted)),
                      ],
                    ),
                    GestureDetector(
                      onTap: _triggerExport,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.limeYellow,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppTheme.ink900, width: 1.2),
                        ),
                        child: Row(
                          children: [
                            Text(
                              _isReportSent ? '✓ SENT' : '↓ EXPORT',
                              style: AppTheme.label(size: 9.5, color: AppTheme.ink900, letterSpacing: 0.1),
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
              NeoCard(
                backgroundColor: AppTheme.white,
                shadowColor: AppTheme.ink900,
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
                          child: Container(color: AppTheme.greenNeon),
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
                        Text('Last synced 7:09 PM', style: AppTheme.body(size: 12, color: AppTheme.muted)),
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
            ],
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
}
