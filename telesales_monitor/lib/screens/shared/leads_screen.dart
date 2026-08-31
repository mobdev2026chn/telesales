import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../widgets/lead_detail_sheet.dart';
import '../../widgets/create_lead_dialog.dart';
import '../../providers/tele_provider.dart';
import '../../models/lead_model.dart';
import '../caller/call_session_screen.dart';

class LeadsScreen extends StatefulWidget {
  const LeadsScreen({super.key});

  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> {
  int _selectedFilterIndex = 0; // 0 = ALL, 1 = FRESH, 2 = CALLED, 3 = DUE
  final TextEditingController _searchCtrl = TextEditingController();

  final List<String> _filterTabs = ['ALL', 'FRESH', 'CALLED', 'DUE'];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);
    final allLeads = tele.leads.isNotEmpty ? tele.leads : _getDemoLeads();

    final query = _searchCtrl.text.trim().toLowerCase();
    final cleanDigits = query.replaceAll(RegExp(r'[^0-9]'), '');

    // Search filter
    var filtered = query.isEmpty
        ? allLeads
        : allLeads.where((l) {
            final nameMatch = l.name.toLowerCase().contains(query);
            final phoneMatch = cleanDigits.isNotEmpty && l.phone.replaceAll(RegExp(r'[^0-9]'), '').contains(cleanDigits);
            return nameMatch || phoneMatch;
          }).toList();

    // Tab filter
    if (_selectedFilterIndex == 1) {
      // FRESH
      filtered = filtered.where((l) => l.attempts == 0 || l.status == LeadStatus.newLead).toList();
    } else if (_selectedFilterIndex == 2) {
      // CALLED
      filtered = filtered.where((l) => l.attempts > 0 || l.status == LeadStatus.interested || l.status == LeadStatus.won).toList();
    } else if (_selectedFilterIndex == 3) {
      // DUE
      filtered = filtered.where((l) => l.status == LeadStatus.followUp || l.status == LeadStatus.renewalFollowUp).toList();
    }

    return Scaffold(
      backgroundColor: AppTheme.paper,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.ink900,
        onPressed: () => CreateLeadDialog.show(context),
        child: const Icon(Icons.add, color: AppTheme.limeYellow),
      ),
      body: RefreshIndicator(
        color: AppTheme.greenNeon,
        backgroundColor: AppTheme.ink900,
        onRefresh: () async {
          await tele.fetchBackendData();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: MY LEADS · <COUNT>
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    'MY LEADS · ',
                    style: AppTheme.headline(size: 32, color: AppTheme.ink900),
                  ),
                  Text(
                    '${allLeads.length}',
                    style: AppTheme.headline(size: 32, color: AppTheme.greenNeon),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Search Bar: ⚲ Search lead or phone...
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppTheme.ink900, width: 1.5),
                  boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  style: AppTheme.bodyBold(size: 13, color: AppTheme.ink900),
                  decoration: InputDecoration(
                    hintText: 'Search lead or phone...',
                    hintStyle: AppTheme.body(size: 12.5, color: AppTheme.muted),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.ink900),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.ink900),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Filter Chips Row + START DIALING Button
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(_filterTabs.length, (idx) {
                          final label = _filterTabs[idx];
                          final isSelected = _selectedFilterIndex == idx;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedFilterIndex = idx),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected ? AppTheme.limeYellow : AppTheme.white,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: AppTheme.ink900, width: 1.5),
                                  boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                                ),
                                child: Text(
                                  label,
                                  style: AppTheme.mono(
                                    size: 10.5,
                                    color: AppTheme.ink900,
                                    weight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // START DIALING Button
                  GestureDetector(
                    onTap: () {
                      tele.startCallSession(leads: filtered);
                      CallSessionScreen.push(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.ink900,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppTheme.ink900, width: 1.5),
                        boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.play_arrow_rounded, color: AppTheme.limeYellow, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            'START DIALING',
                            style: AppTheme.label(size: 9.5, color: AppTheme.limeYellow, letterSpacing: 0.12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Leads List Cards
              if (filtered.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AppTheme.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.ink900, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      'NO LEADS MATCH THIS FILTER',
                      style: AppTheme.mono(size: 12, color: AppTheme.muted),
                    ),
                  ),
                )
              else
                ...filtered.map((lead) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildLeadCard(context, lead, tele),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeadCard(BuildContext context, LeadModel lead, TeleProvider tele) {
    // Badge info
    String badgeText = 'FRESH · NOT DIALED';
    Color badgeBg = AppTheme.white;
    Color badgeFg = AppTheme.ink900;
    bool isExhausted = false;

    if (lead.status == LeadStatus.followUp || lead.status == LeadStatus.renewalFollowUp) {
      badgeText = 'FOLLOW-UP · OVERDUE';
      badgeBg = AppTheme.limeYellow;
      badgeFg = AppTheme.ink900;
    } else if (lead.status == LeadStatus.interested) {
      badgeText = 'INTERESTED';
      badgeBg = AppTheme.greenNeon;
      badgeFg = AppTheme.ink900;
    } else if (lead.status == LeadStatus.lost || lead.status == LeadStatus.notInterested) {
      badgeText = 'EXHAUSTED · 3/3 RETRIES';
      badgeBg = const Color(0xFFFDECEB);
      badgeFg = AppTheme.redOverdue;
      isExhausted = true;
    } else if (lead.attempts > 0) {
      badgeText = '${lead.attempts}× DIALED';
    }

    final cardBg = isExhausted ? const Color(0xFFF7F4EB) : AppTheme.white;

    return GestureDetector(
      onTap: () => LeadDetailSheet.show(context, {
        'id': lead.id,
        'name': lead.name,
        'phone': lead.phone,
        'status': lead.statusLabel,
        'note': lead.note,
        'attempts': lead.attempts,
      }),
      child: NeoCard(
        backgroundColor: cardBg,
        shadowColor: AppTheme.ink900,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lead.name,
                    style: AppTheme.bodyBold(size: 15, color: isExhausted ? AppTheme.muted : AppTheme.ink900),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    lead.attempts > 0 ? '${lead.phone} · ${lead.attempts}× dialed' : lead.phone,
                    style: AppTheme.mono(size: 11, color: AppTheme.muted),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: isExhausted ? AppTheme.redOverdue.withValues(alpha: 0.5) : AppTheme.ink900, width: 1.2),
                    ),
                    child: Text(
                      badgeText,
                      style: AppTheme.mono(
                        size: 9,
                        color: badgeFg,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Circular DIAL Button
            GestureDetector(
              onTap: () {
                tele.startCallSession(leads: [lead]);
                CallSessionScreen.push(context, lead: lead);
              },
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppTheme.greenNeon,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.ink900, width: 1.5),
                  boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                ),
                child: Center(
                  child: Text(
                    'DIAL',
                    style: AppTheme.mono(size: 10.5, color: AppTheme.ink900, weight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<LeadModel> _getDemoLeads() {
    return [
      LeadModel(
        id: 'l1',
        name: 'Ganesh Enterprises',
        phone: '+91 98400 11223',
        status: LeadStatus.newLead,
        attempts: 0,
        dateAdded: DateTime.now(),
        lastCallDate: DateTime.now(),
        note: 'New inquiry',
      ),
      LeadModel(
        id: 'l2',
        name: 'Lakshmi Traders',
        phone: '+91 90940 55667',
        status: LeadStatus.newLead,
        attempts: 0,
        dateAdded: DateTime.now(),
        lastCallDate: DateTime.now(),
        note: 'Wholesale client',
      ),
      LeadModel(
        id: 'l3',
        name: 'Meenakshi Agencies',
        phone: '+91 90250 11876',
        status: LeadStatus.followUp,
        attempts: 1,
        dateAdded: DateTime.now(),
        lastCallDate: DateTime.now(),
        note: 'Follow-up on quote',
      ),
      LeadModel(
        id: 'l4',
        name: 'Bharat Electricals',
        phone: '+91 97890 33445',
        status: LeadStatus.interested,
        attempts: 1,
        dateAdded: DateTime.now(),
        lastCallDate: DateTime.now(),
        note: 'Interested in annual package',
      ),
      LeadModel(
        id: 'l5',
        name: 'Annai Pharma',
        phone: '+91 99400 77889',
        status: LeadStatus.lost,
        attempts: 3,
        dateAdded: DateTime.now(),
        lastCallDate: DateTime.now(),
        note: 'No response after 3 retries',
      ),
      LeadModel(
        id: 'l6',
        name: 'Chennai Silks Outlet',
        phone: '+91 95510 22110',
        status: LeadStatus.followUp,
        attempts: 2,
        dateAdded: DateTime.now(),
        lastCallDate: DateTime.now(),
        note: 'Callback scheduled for 4 PM',
      ),
      LeadModel(
        id: 'l7',
        name: 'Velan Hardware',
        phone: '+91 98410 44556',
        status: LeadStatus.newLead,
        attempts: 0,
        dateAdded: DateTime.now(),
        lastCallDate: DateTime.now(),
        note: 'Hardware tools inquiry',
      ),
    ];
  }
}
