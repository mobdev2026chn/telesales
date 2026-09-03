import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
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
  String _selectedCategory = 'ALL';
  String _selectedTeamMember = 'ALL';
  final TextEditingController _searchCtrl = TextEditingController();

  final List<String> _categoryOptions = [
    'ALL',
    'NEW',
    'INTERESTED',
    'FOLLOW-UP',
    'CONVERTED',
    'NOT INTERESTED',
    'Follow up',
    'Book Demo',
    'Demo Reschedule',
    'Demo Done',
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _formatRelativeDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0 && dt.day == now.day) {
      return 'Today · ${DateFormat('h:mm a').format(dt)}';
    } else if (diff.inDays <= 1) {
      return 'Yesterday · ${DateFormat('h:mm a').format(dt)}';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return DateFormat('d MMM yyyy').format(dt);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);
    final isManager = tele.currentRole == UserRole.manager && !tele.isManagerCallerMode;

    // 1. Scoping Leads:
    // Caller: ONLY leads assigned to this caller
    // Manager: Leads assigned to callers reporting to this manager / team
    List<LeadModel> baseLeads = List<LeadModel>.from(tele.leads);

    if (!isManager) {
      // Caller view: ONLY their leads should be displayed
      final myName = tele.callerName.trim().toLowerCase();
      final myId = tele.currentUserId.trim().toLowerCase();
      final myPhone = tele.verifiedTrackingNumber.trim();

      baseLeads = baseLeads.where((l) {
        final ass = l.assignedTo.trim().toLowerCase();
        final matchesName = myName.isNotEmpty && (ass == myName || ass.contains(myName) || myName.contains(ass));
        final matchesId = myId.isNotEmpty && ass == myId;
        final matchesPhone = myPhone.isNotEmpty && l.assignedTo == myPhone;
        return matchesName || matchesId || matchesPhone;
      }).toList();
    } else {
      // Manager view: filter by selected team member if chosen
      if (_selectedTeamMember != 'ALL') {
        baseLeads = baseLeads.where((l) {
          return l.assignedTo.toLowerCase() == _selectedTeamMember.toLowerCase();
        }).toList();
      }
    }

    // 2. Search filtering
    final query = _searchCtrl.text.trim().toLowerCase();
    final cleanDigits = query.replaceAll(RegExp(r'[^0-9]'), '');

    var filtered = query.isEmpty
        ? baseLeads
        : baseLeads.where((l) {
            final nameMatch = l.name.toLowerCase().contains(query);
            final phoneMatch = cleanDigits.isNotEmpty && l.phone.replaceAll(RegExp(r'[^0-9]'), '').contains(cleanDigits);
            return nameMatch || phoneMatch;
          }).toList();

    // 3. Category filtering (Matching exact filters from user specification)
    if (_selectedCategory != 'ALL') {
      filtered = filtered.where((l) {
        final cat = _selectedCategory.toUpperCase().replaceAll(RegExp(r'[\s_-]'), '');
        final lStatus = l.statusLabel.toUpperCase().replaceAll(RegExp(r'[\s_-]'), '');
        final lEnum = l.status.name.toUpperCase().replaceAll(RegExp(r'[\s_-]'), '');

        if (cat == 'NEW') {
          return l.status == LeadStatus.newLead || l.status == LeadStatus.newFollowUp;
        }
        if (cat == 'INTERESTED') {
          return l.status == LeadStatus.interested;
        }
        if (cat == 'FOLLOWUP') {
          return l.status == LeadStatus.followUp || l.status == LeadStatus.bookDemo || l.status == LeadStatus.demoReschedule || l.status == LeadStatus.newFollowUp;
        }
        if (cat == 'CONVERTED') {
          return l.status == LeadStatus.won || l.status == LeadStatus.demoDone;
        }
        if (cat == 'NOTINTERESTED') {
          return l.status == LeadStatus.notInterested || l.status == LeadStatus.lost;
        }
        if (cat == 'BOOKDEMO') {
          return l.status == LeadStatus.bookDemo;
        }
        if (cat == 'DEMORESCHEDULE') {
          return l.status == LeadStatus.demoReschedule;
        }
        if (cat == 'DEMODONE') {
          return l.status == LeadStatus.demoDone || l.status == LeadStatus.won;
        }
        return lStatus.contains(cat) || lEnum.contains(cat);
      }).toList();
    }

    // Team members options for Manager
    final List<String> managerTeamCallers = ['ALL'];
    if (isManager) {
      for (var emp in tele.employees) {
        if (emp.role.toLowerCase() == 'caller') {
          managerTeamCallers.add(emp.name);
        }
      }
    }

    return Scaffold(
      backgroundColor: AppTheme.paper,
      // Only callers have the Add Lead FAB (Removed duplicate buttons and removed from manager side)
      floatingActionButton: !isManager
          ? FloatingActionButton(
              backgroundColor: AppTheme.ink900,
              onPressed: () => CreateLeadDialog.show(context),
              child: const Icon(Icons.add, color: AppTheme.limeYellow),
            )
          : null,
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
              // Header: (MY LEADS / TEAM LEADS) · <COUNT>
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    isManager ? 'TEAM LEADS · ' : 'MY LEADS · ',
                    style: AppTheme.headline(size: 28, color: AppTheme.ink900),
                  ),
                  Text(
                    '${filtered.length}',
                    style: AppTheme.headline(size: 28, color: AppTheme.greenNeon),
                  ),
                  if (isManager) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.limeYellow,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.ink900, width: 1),
                      ),
                      child: Text('MONITORING ONLY', style: AppTheme.label(size: 8, color: AppTheme.ink900)),
                    ),
                  ],
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
              const SizedBox(height: 12),

              // Filters Row:
              // For Caller: 7 Categories Dropdown
              // For Manager: Team Members Dropdown + 7 Categories Dropdown
              Row(
                children: [
                  // Team Members Dropdown (Manager ONLY)
                  if (isManager) ...[
                    Expanded(
                      flex: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.ink900, width: 1.5),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: managerTeamCallers.contains(_selectedTeamMember) ? _selectedTeamMember : 'ALL',
                            isExpanded: true,
                            dropdownColor: AppTheme.white,
                            icon: const Icon(Icons.arrow_drop_down, color: AppTheme.ink900),
                            style: AppTheme.bodyBold(size: 11, color: AppTheme.ink900),
                            onChanged: (v) {
                              if (v != null) setState(() => _selectedTeamMember = v);
                            },
                            items: managerTeamCallers.map((m) {
                              return DropdownMenuItem(
                                value: m,
                                child: Text(m == 'ALL' ? '👥 ALL MEMBERS' : '👤 $m', overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // 7 Categories Dropdown (Both Caller & Manager)
                  Expanded(
                    flex: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.ink900, width: 1.5),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _categoryOptions.contains(_selectedCategory) ? _selectedCategory : 'ALL',
                          isExpanded: true,
                          dropdownColor: AppTheme.white,
                          icon: const Icon(Icons.filter_alt_outlined, size: 16, color: AppTheme.ink900),
                          style: AppTheme.bodyBold(size: 11, color: AppTheme.ink900),
                          onChanged: (v) {
                            if (v != null) setState(() => _selectedCategory = v);
                          },
                          items: _categoryOptions.map((c) {
                            return DropdownMenuItem(
                              value: c,
                              child: Text(c == 'ALL' ? '🏷️ ALL CATEGORIES' : c, overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),

                  // START DIALING (Only visible to Callers or Manager in Caller Mode)
                  if (!isManager) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        tele.startCallSession(leads: filtered);
                        CallSessionScreen.push(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: AppTheme.ink900,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.ink900, width: 1.5),
                          boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.play_arrow_rounded, color: AppTheme.limeYellow, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              'AUTO DIAL',
                              style: AppTheme.label(size: 9.5, color: AppTheme.limeYellow, letterSpacing: 0.12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
                      'NO LEADS FOUND FOR THIS SELECTION',
                      style: AppTheme.mono(size: 12, color: AppTheme.muted),
                    ),
                  ),
                )
              else
                ...filtered.map((lead) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildLeadCard(context, lead, tele, isManager: isManager),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeadCard(BuildContext context, LeadModel lead, TeleProvider tele, {required bool isManager}) {
    final cleanPhone = lead.phone.replaceAll(RegExp(r'[^0-9]'), '');
    final last10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;

    // Calculate dynamic attempts from device call logs
    final actualAttempts = tele.allCallLogs.where((c) {
      final cClean = c.phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
      return last10.isNotEmpty && cClean.endsWith(last10);
    }).length;

    final displayAttempts = actualAttempts > lead.attempts ? actualAttempts : lead.attempts;

    // Badge styling based on category
    String badgeText = lead.statusLabel.toUpperCase();
    Color badgeBg = AppTheme.limeYellow;
    Color badgeFg = AppTheme.ink900;

    switch (lead.status) {
      case LeadStatus.newFollowUp:
      case LeadStatus.newLead:
        badgeText = 'NEW';
        badgeBg = AppTheme.limeYellow;
        badgeFg = AppTheme.ink900;
        break;
      case LeadStatus.interested:
        badgeText = 'INTERESTED';
        badgeBg = AppTheme.greenNeon;
        badgeFg = AppTheme.ink900;
        break;
      case LeadStatus.followUp:
        badgeText = 'FOLLOW-UP';
        badgeBg = AppTheme.limeYellow;
        badgeFg = AppTheme.ink900;
        break;
      case LeadStatus.won:
        badgeText = 'CONVERTED';
        badgeBg = AppTheme.greenNeon;
        badgeFg = AppTheme.ink900;
        break;
      case LeadStatus.lost:
      case LeadStatus.notInterested:
        badgeText = 'NOT INTERESTED';
        badgeBg = const Color(0xFFECEFF1);
        badgeFg = AppTheme.muted;
        break;
      case LeadStatus.bookDemo:
        badgeText = 'BOOK DEMO';
        badgeBg = AppTheme.greenNeon;
        badgeFg = AppTheme.ink900;
        break;
      case LeadStatus.demoReschedule:
        badgeText = 'DEMO RESCHEDULE';
        badgeBg = const Color(0xFFFFF3CD);
        badgeFg = const Color(0xFF856404);
        break;
      case LeadStatus.demoDone:
        badgeText = 'DEMO DONE';
        badgeBg = AppTheme.ink900;
        badgeFg = AppTheme.limeYellow;
        break;
      case LeadStatus.notPickup:
        badgeText = 'NOT PICK UP';
        badgeBg = const Color(0xFFFDECEB);
        badgeFg = AppTheme.redOverdue;
        break;
      case LeadStatus.busyOnCall:
        badgeText = 'BUSY ON CALL';
        badgeBg = const Color(0xFFFFF3CD);
        badgeFg = const Color(0xFF856404);
        break;
      case LeadStatus.renewalFollowUp:
        badgeText = 'RENEWAL FOLLOW UP';
        badgeBg = AppTheme.greenNeon.withValues(alpha: 0.3);
        badgeFg = AppTheme.greenDark;
        break;
      case LeadStatus.warned:
        badgeText = 'WARNED';
        badgeBg = const Color(0xFFFFE0B2);
        badgeFg = const Color(0xFFE65100);
        break;
      case LeadStatus.other:
        badgeText = 'OTHER';
        badgeBg = AppTheme.white;
        badgeFg = AppTheme.ink900;
        break;
    }

    final dateLabel = _formatRelativeDate(lead.lastCallDate);

    return GestureDetector(
      onTap: () {
        if (!isManager) {
          // Caller can view and edit status
          LeadDetailSheet.show(context, {
            'id': lead.id,
            'name': lead.name,
            'phone': lead.phone,
            'status': lead.statusLabel,
            'note': lead.note,
            'attempts': displayAttempts,
          });
        } else {
          // Manager has read-only monitoring view (No editing, as requested)
          _showManagerReadOnlyLeadDialog(context, lead, displayAttempts, dateLabel);
        }
      },
      child: NeoCard(
        backgroundColor: AppTheme.white,
        shadowColor: AppTheme.ink900,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lead.name,
                          style: AppTheme.bodyBold(size: 15, color: AppTheme.ink900),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (lead.assignedTo.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.paper,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppTheme.ink900, width: 0.8),
                          ),
                          child: Text(
                            lead.assignedTo.toUpperCase(),
                            style: AppTheme.mono(size: 8, color: AppTheme.ink900),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    displayAttempts > 0 ? '${lead.phone} · $displayAttempts× dialed' : '${lead.phone} · Not dialed yet',
                    style: AppTheme.mono(size: 11, color: AppTheme.muted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Last activity: $dateLabel',
                    style: AppTheme.mono(size: 9.5, color: AppTheme.muted),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppTheme.ink900, width: 1.2),
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

            // DIAL Button (Only for Callers)
            if (!isManager)
              GestureDetector(
                onTap: () {
                  tele.startCallSession(leads: [lead]);
                  CallSessionScreen.push(context, lead: lead);
                },
                child: Container(
                  width: 52,
                  height: 52,
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
              )
            else
              // Manager view indicator
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.paper,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.ink900, width: 1),
                ),
                child: const Icon(Icons.remove_red_eye_outlined, size: 18, color: AppTheme.ink900),
              ),
          ],
        ),
      ),
    );
  }

  void _showManagerReadOnlyLeadDialog(BuildContext context, LeadModel lead, int attempts, String dateStr) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.ink900, width: 2),
        ),
        title: Row(
          children: [
            const Icon(Icons.verified_user_rounded, color: AppTheme.greenDark, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(lead.name, style: AppTheme.headline(size: 16))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PHONE: ${lead.phone}', style: AppTheme.mono(size: 12, color: AppTheme.ink900)),
            const SizedBox(height: 6),
            Text('STATUS: ${lead.statusLabel.toUpperCase()}', style: AppTheme.bodyBold(size: 12, color: AppTheme.greenDark)),
            const SizedBox(height: 6),
            Text('ASSIGNED TO: ${lead.assignedTo.isNotEmpty ? lead.assignedTo : "Unassigned"}', style: AppTheme.body(size: 12)),
            const SizedBox(height: 6),
            Text('CALL ATTEMPTS: $attempts', style: AppTheme.mono(size: 12)),
            const SizedBox(height: 6),
            Text('LAST ACTIVITY: $dateStr', style: AppTheme.mono(size: 11, color: AppTheme.muted)),
            if (lead.note.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('CALLER NOTES:', style: AppTheme.label(size: 9, color: AppTheme.muted)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.ink900, width: 1),
                ),
                child: Text(lead.note, style: AppTheme.body(size: 11)),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CLOSE', style: AppTheme.label(size: 11, color: AppTheme.ink900)),
          ),
        ],
      ),
    );
  }
}
