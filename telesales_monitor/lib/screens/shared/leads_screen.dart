import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../widgets/top_header.dart';
import '../../widgets/lead_detail_sheet.dart';
import '../../widgets/save_contact_dialog.dart';
import '../../providers/tele_provider.dart';

class LeadsScreen extends StatefulWidget {
  const LeadsScreen({super.key});

  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> {
  int _selectedFilterIndex = 0;
  String _selectedTeamMember = 'ALL TEAM MEMBERS';

  void _showTeamMemberPicker(BuildContext context, TeleProvider tele) {
    final List<String> memberOptions = <String>{
      'ALL TEAM MEMBERS',
      if (tele.callerName.isNotEmpty) tele.callerName.toUpperCase(),
      ...tele.employees.map((e) => e.name.toUpperCase()),
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
                'SELECT TEAM MEMBER',
                style: AppTheme.headline(size: 14, color: AppTheme.ink900),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: memberOptions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, idx) {
                    final option = memberOptions[idx];
                    final isSelected = _selectedTeamMember == option;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedTeamMember = option;
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

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);

    final callerName = tele.currentUserName.toUpperCase();

    // Dynamic Leads List from Provider
    final List<Map<String, dynamic>> dynamicLeads = [];

    for (var l in tele.filteredLeads) {
      String bType = 'outline';
      String statusStr = 'NEW';
      if (l.status.name == 'won') {
        bType = 'green';
        statusStr = 'WON';
      } else if (l.status.name == 'interested') {
        bType = 'lime';
        statusStr = 'INTERESTED';
      } else if (l.status.name == 'followUp') {
        bType = 'lime';
        statusStr = 'FOLLOW-UP CALL';
      }

      dynamicLeads.add({
        'name': l.name,
        'phone': l.phone,
        'status': statusStr,
        'attempts': '${l.attempts} attempts · Today',
        'badgeType': bType,
      });
    }

    final totalCount = dynamicLeads.length;

    final filterOptions = [
      {'label': 'ALL · $totalCount', 'filter': 'ALL'},
      {'label': 'WON', 'filter': 'WON'},
      {'label': 'FOLLOW-UP CALL', 'filter': 'FOLLOW-UP'},
      {'label': 'INTERESTED', 'filter': 'INTERESTED'},
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
            TopHeader(
              title: 'LEADS',
              userName: callerName,
              selectedSimIndex: 1,
            ),
            const SizedBox(height: 14),

            // Dropdown: ALL TEAM MEMBERS
            GestureDetector(
              onTap: () => _showTeamMemberPicker(context, tele),
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
                      _selectedTeamMember,
                      style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.14),
                    ),
                    const Icon(Icons.keyboard_arrow_down, size: 20, color: AppTheme.ink900),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Filter Chips Row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(filterOptions.length, (index) {
                  final isSel = _selectedFilterIndex == index;
                  final label = filterOptions[index]['label']!;

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _selectedFilterIndex = index);
                        tele.setLeadFilter(filterOptions[index]['filter']!);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: isSel ? AppTheme.ink900 : AppTheme.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppTheme.ink900, width: 1.2),
                        ),
                        child: Text(
                          label,
                          style: AppTheme.label(
                            size: 9.5,
                            color: isSel ? AppTheme.limeYellow : AppTheme.ink900,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
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
                  // Donut Graphic
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
                            value: totalCount > 0 ? 0.70 : 0.05,
                            strokeWidth: 10,
                            backgroundColor: AppTheme.greenDark,
                            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.greenNeon),
                          ),
                        ),
                        Text(
                          '$totalCount',
                          style: AppTheme.headline(size: 26, color: AppTheme.white),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),

                  // Pipeline Summary Legend
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PIPELINE STATUS',
                          style: AppTheme.label(size: 9, color: AppTheme.limeYellow, letterSpacing: 0.18),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(width: 6, height: 6, color: AppTheme.greenNeon),
                            const SizedBox(width: 6),
                            Text('Won ${tele.leads.where((l) => l.status.name == 'won').length} · ', style: AppTheme.body(size: 11, color: AppTheme.white)),
                            Container(width: 6, height: 6, color: AppTheme.limeYellow),
                            const SizedBox(width: 6),
                            Text('Interested ${tele.leads.where((l) => l.status.name == 'interested').length}', style: AppTheme.body(size: 11, color: AppTheme.white)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '• Follow-up ${tele.leads.where((l) => l.status.name == 'followUp').length} · Total $totalCount',
                          style: AppTheme.body(size: 11, color: AppTheme.lightMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Leads Items List
            if (dynamicLeads.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.people_outline, size: 44, color: AppTheme.muted),
                      const SizedBox(height: 10),
                      Text('NO LEADS YET', style: AppTheme.headline(size: 18)),
                      const SizedBox(height: 4),
                      Text(
                        'Leads generated from phone calls will appear here.',
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
                itemCount: dynamicLeads.length,
                separatorBuilder: (ctx, i) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final lead = dynamicLeads[i];
                  final name = lead['name'] as String;
                  final phone = lead['phone'] as String;
                  final status = lead['status'] as String;
                  final attempts = lead['attempts'] as String;
                  final badgeType = lead['badgeType'] as String;

                  Color badgeBg = AppTheme.white;
                  Color badgeText = AppTheme.ink900;
                  if (badgeType == 'lime') {
                    badgeBg = AppTheme.greenGrass;
                  } else if (badgeType == 'green') {
                    badgeBg = AppTheme.greenNeon;
                    badgeText = AppTheme.white;
                  } else if (badgeType == 'dark') {
                    badgeBg = AppTheme.ink900;
                    badgeText = AppTheme.limeYellow;
                  }

                  final isUnsaved = name == phone || name == 'Unknown';

                  return NeoCard(
                    backgroundColor: AppTheme.white,
                    shadowColor: AppTheme.ink900,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    onTap: () => LeadDetailSheet.show(context, lead),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      name,
                                      style: AppTheme.bodyBold(size: 14, color: AppTheme.ink900),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => SaveContactDialog.show(context, phone, initialName: isUnsaved ? null : name),
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
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: badgeBg,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: AppTheme.ink900, width: 1),
                              ),
                              child: Text(
                                status,
                                style: AppTheme.label(size: 8.5, color: badgeText),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              phone,
                              style: AppTheme.mono(size: 11, color: AppTheme.ink700),
                            ),
                            Text(
                              attempts,
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
          ],
        ),
      ),
    );
  }
}
