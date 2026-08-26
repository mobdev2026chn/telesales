import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import 'neo_button.dart';
import '../providers/tele_provider.dart';
import '../models/lead_model.dart';

class LeadDetailSheet extends StatefulWidget {
  final Map<String, dynamic> leadData;

  const LeadDetailSheet({
    super.key,
    required this.leadData,
  });

  static void show(BuildContext context, Map<String, dynamic> leadData) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LeadDetailSheet(leadData: leadData),
    );
  }

  @override
  State<LeadDetailSheet> createState() => _LeadDetailSheetState();
}

class _LeadDetailSheetState extends State<LeadDetailSheet> {
  late String _selectedStatus;
  late TextEditingController _noteCtrl;

  final List<String> _statuses = [
    'NEW',
    'FOLLOW-UP CALL',
    'NOT PICKUP',
    'BUSY ON CALL',
    'RENEWAL FOLLOW-UP',
    'INTERESTED',
    'WON',
    'LOST',
  ];

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.leadData['status'] as String? ?? 'NEW';
    final existingNote = widget.leadData['note'] as String? ?? '';
    _noteCtrl = TextEditingController(text: existingNote);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  LeadStatus _parseStatus(String str) {
    switch (str.toUpperCase()) {
      case 'WON':
        return LeadStatus.won;
      case 'INTERESTED':
        return LeadStatus.interested;
      case 'FOLLOW-UP CALL':
      case 'FOLLOWUP':
        return LeadStatus.followUp;
      case 'NOT PICKUP':
        return LeadStatus.notPickup;
      case 'BUSY ON CALL':
        return LeadStatus.busyOnCall;
      case 'RENEWAL FOLLOW-UP':
        return LeadStatus.renewalFollowUp;
      case 'LOST':
        return LeadStatus.lost;
      default:
        return LeadStatus.newLead;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context, listen: false);

    final leadId = widget.leadData['id'] as String? ?? UniqueKey().toString();
    final name = (widget.leadData['name'] as String? ?? 'LEAD CLIENT').toUpperCase();
    final phone = widget.leadData['phone'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Drag Handle
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

            // Top Header: LEAD DETAILS & Close Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'LEAD DETAILS',
                  style: AppTheme.mono(size: 10, color: AppTheme.muted),
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
            const SizedBox(height: 4),

            // Lead Name & Phone
            Text(
              name,
              style: AppTheme.headline(size: 22, color: AppTheme.ink900),
            ),
            const SizedBox(height: 2),
            Text(
              phone,
              style: AppTheme.mono(size: 12, color: AppTheme.ink700),
            ),
            const SizedBox(height: 16),

            // 3 Action Buttons: CALL, WHATSAPP, SMS
            Row(
              children: [
                Expanded(
                  child: NeoButton(
                    backgroundColor: AppTheme.ink900,
                    shadowColor: AppTheme.greenNeon,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                    onTap: () {
                      Navigator.of(context).pop();
                      tele.launchCall(phone);
                    },
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'CALL',
                          style: AppTheme.label(size: 10, color: AppTheme.limeYellow),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: NeoButton(
                    backgroundColor: AppTheme.white,
                    shadowColor: AppTheme.ink900,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                    onTap: () {
                      Navigator.of(context).pop();
                      tele.launchWhatsApp(phone);
                    },
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'WHATSAPP',
                          style: AppTheme.label(size: 10, color: AppTheme.ink900),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: NeoButton(
                    backgroundColor: AppTheme.white,
                    shadowColor: AppTheme.ink900,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                    onTap: () {
                      Navigator.of(context).pop();
                      tele.launchSMS(phone);
                    },
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'SMS',
                          style: AppTheme.label(size: 10, color: AppTheme.ink900),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Section Header: LEAD STATUS
            Row(
              children: [
                Container(width: 8, height: 8, color: AppTheme.greenNeon),
                const SizedBox(width: 8),
                Text(
                  'UPDATE LEAD STATUS',
                  style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.18),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Status Wrap Grid
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _statuses.map((st) {
                final isSelected = _selectedStatus == st;
                return GestureDetector(
                  onTap: () => setState(() => _selectedStatus = st),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.ink900 : AppTheme.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppTheme.ink900, width: 1.2),
                    ),
                    child: Text(
                      st,
                      style: AppTheme.label(
                        size: 9,
                        color: isSelected ? AppTheme.limeYellow : AppTheme.ink900,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),

            // Section Header: CALL NOTES & REMARKS
            Row(
              children: [
                Container(width: 8, height: 8, color: AppTheme.greenNeon),
                const SizedBox(width: 8),
                Text(
                  'CALL NOTES & REMARKS',
                  style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.18),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Notes Text Area Input
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.ink900, width: 1.5),
                boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
              ),
              child: TextField(
                controller: _noteCtrl,
                maxLines: 3,
                style: AppTheme.body(size: 12, color: AppTheme.ink900),
                decoration: const InputDecoration(
                  hintText: 'Add notes about this lead or pricing discussion...',
                  hintStyle: TextStyle(color: AppTheme.muted, fontSize: 12),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // SAVE LEAD STATUS Button
            NeoButton(
              backgroundColor: AppTheme.ink900,
              shadowColor: AppTheme.greenNeon,
              onTap: () {
                tele.updateLeadStatus(leadId, _parseStatus(_selectedStatus));
                if (_noteCtrl.text.isNotEmpty) {
                  tele.addLeadNote(leadId, _noteCtrl.text);
                }
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppTheme.ink900,
                    content: Text(
                      'Lead status updated to $_selectedStatus',
                      style: AppTheme.bodyBold(size: 12, color: AppTheme.limeYellow),
                    ),
                  ),
                );
              },
              child: Center(
                child: Text(
                  'SAVE LEAD STATUS →',
                  style: AppTheme.label(size: 11, color: AppTheme.limeYellow, letterSpacing: 0.14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
