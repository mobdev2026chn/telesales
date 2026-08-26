import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../widgets/neo_button.dart';
import '../../providers/tele_provider.dart';
import '../../models/lead_model.dart';

class LeadsScreen extends StatelessWidget {
  const LeadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);
    final currentDateStr = DateFormat('d MMM yyyy').format(DateTime.now()).toUpperCase();
    final leads = tele.leads;

    final filterOptions = [
      {'label': 'ALL', 'filter': 'ALL'},
      {'label': 'NEW', 'filter': 'NEW'},
      {'label': 'FOLLOW-UP CALL', 'filter': 'FOLLOW-UP'},
      {'label': 'INTERESTED', 'filter': 'INTERESTED'},
      {'label': 'WON', 'filter': 'WON'},
      {'label': 'LOST', 'filter': 'LOST'},
    ];

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
                          'LEADS',
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
            const SizedBox(height: 14),

            // Filter Pills Row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: filterOptions.map((opt) {
                  final isSel = tele.leadFilter == opt['filter'];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => tele.setLeadFilter(opt['filter'] as String),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSel ? AppTheme.ink900 : AppTheme.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppTheme.ink900, width: 1.5),
                          boxShadow: isSel ? AppTheme.neoShadowSm(color: AppTheme.ink900) : null,
                        ),
                        child: Text(
                          opt['label'] as String,
                          style: AppTheme.label(
                            size: 11,
                            color: isSel ? AppTheme.white : AppTheme.ink900,
                            letterSpacing: 0.12,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 14),

            // Pipeline Status Donut Card
            NeoCard(
              backgroundColor: AppTheme.ink900,
              shadowColor: AppTheme.ink900,
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  // Donut Chart Graphic
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 68,
                          height: 68,
                          child: CircularProgressIndicator(
                            value: 0.75,
                            strokeWidth: 9,
                            backgroundColor: const Color(0xFF3DC838).withValues(alpha: 0.25),
                            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.greenNeon),
                          ),
                        ),
                        Text(
                          '${leads.length}',
                          style: AppTheme.headline(size: 24, color: AppTheme.white),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),

                  // Pipeline Legend
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PIPELINE STATUS',
                          style: AppTheme.label(size: 9, color: AppTheme.limeYellow, letterSpacing: 0.18),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(width: 6, height: 6, color: AppTheme.greenNeon),
                            const SizedBox(width: 6),
                            Text('Won 12 · ', style: AppTheme.body(size: 11, color: AppTheme.white)),
                            Container(width: 6, height: 6, color: AppTheme.limeYellow),
                            const SizedBox(width: 6),
                            Text('Interested 18', style: AppTheme.body(size: 11, color: AppTheme.white)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(width: 6, height: 6, color: AppTheme.greenGrass),
                            const SizedBox(width: 6),
                            Text('Follow-up 21 · ', style: AppTheme.body(size: 11, color: AppTheme.lightMuted)),
                            Container(width: 6, height: 6, color: AppTheme.muted),
                            const SizedBox(width: 6),
                            Text('Other 33', style: AppTheme.body(size: 11, color: AppTheme.lightMuted)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Lead Cards
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: leads.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final lead = leads[index];
                final pillStyle = _getLeadPillStyle(lead.status);

                return NeoCard(
                  backgroundColor: AppTheme.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              lead.name,
                              style: AppTheme.bodyBold(size: 15, color: AppTheme.ink900),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: pillStyle.backgroundColor,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: AppTheme.ink900, width: 1),
                            ),
                            child: Text(
                              lead.statusLabel.toUpperCase(),
                              style: AppTheme.label(
                                size: 8,
                                color: pillStyle.textColor,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            lead.phone,
                            style: AppTheme.mono(size: 11, color: AppTheme.ink700),
                          ),
                          Text(
                            '${lead.attempts} attempts · Today',
                            style: AppTheme.mono(size: 10, color: AppTheme.muted),
                          ),
                        ],
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

  _PillStyle _getLeadPillStyle(LeadStatus status) {
    switch (status) {
      case LeadStatus.won:
        return _PillStyle(backgroundColor: const Color(0xFF22C55E), textColor: AppTheme.white);
      case LeadStatus.interested:
      case LeadStatus.followUp:
        return _PillStyle(backgroundColor: AppTheme.limeYellow, textColor: AppTheme.ink900);
      case LeadStatus.renewalFollowUp:
        return _PillStyle(backgroundColor: AppTheme.ink900, textColor: AppTheme.greenNeon);
      case LeadStatus.notPickup:
      case LeadStatus.busyOnCall:
      case LeadStatus.newLead:
      default:
        return _PillStyle(backgroundColor: AppTheme.white, textColor: AppTheme.ink700);
    }
  }
}

class _PillStyle {
  final Color backgroundColor;
  final Color textColor;
  _PillStyle({required this.backgroundColor, required this.textColor});
}
