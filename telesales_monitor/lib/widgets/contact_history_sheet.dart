import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import 'neo_card.dart';
import 'neo_button.dart';
import 'reschedule_sheet.dart';
import '../providers/tele_provider.dart';
import '../models/call_log_model.dart';

class ContactHistorySheet extends StatelessWidget {
  final Map<String, dynamic> contactData;

  const ContactHistorySheet({
    super.key,
    required this.contactData,
  });

  static void show(BuildContext context, Map<String, dynamic> contactData) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ContactHistorySheet(contactData: contactData),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context, listen: false);

    final name = (contactData['name'] as String? ?? 'CONTACT').toUpperCase();
    final phone = contactData['phone'] as String? ?? '';
    final rawLogs = contactData['rawLogs'] as List<CallLogModel>?;

    final List<Map<String, dynamic>> historyEvents = [];

    if (rawLogs != null && rawLogs.isNotEmpty) {
      for (var c in rawLogs) {
        String typeStr = 'Outgoing';
        IconData iconData = Icons.arrow_upward;
        if (c.type == CallType.incoming) {
          typeStr = 'Incoming';
          iconData = Icons.arrow_downward;
        } else if (c.type == CallType.missed) {
          typeStr = 'Missed';
          iconData = Icons.undo;
        } else if (c.type == CallType.rejected) {
          typeStr = 'Rejected';
          iconData = Icons.block;
        }

        historyEvents.add({
          'type': typeStr,
          'time': '${c.timestamp.hour}:${c.timestamp.minute.toString().padLeft(2, '0')}',
          'duration': c.duration.inSeconds > 0 ? c.durationFormatted : '0s',
          'icon': iconData,
        });
      }
    }

    final totalCallsCount = historyEvents.length;

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

            // Top Header: CONTACT & Close Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'CONTACT HISTORY',
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

            // Contact Name & Phone
            Text(
              name,
              style: AppTheme.headline(size: 24, color: AppTheme.ink900),
            ),
            const SizedBox(height: 2),
            Text(
              phone,
              style: AppTheme.mono(size: 12, color: AppTheme.ink700),
            ),
            const SizedBox(height: 16),

            // 3-Button Actions: CALL BACK, WHATSAPP, + FOLLOW-UP
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
                          'CALL BACK',
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
                      RescheduleSheet.show(context, contactName: name, phone: phone);
                    },
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '+ FOLLOW-UP',
                          style: AppTheme.label(size: 10, color: AppTheme.ink900),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Section Header: TIMELINE
            Row(
              children: [
                Container(width: 8, height: 8, color: AppTheme.greenNeon),
                const SizedBox(width: 8),
                Text(
                  'TIMELINE · $totalCallsCount CALLS LOGGED',
                  style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.18),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Timeline Items
            if (historyEvents.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    'No logged call history for this contact.',
                    style: AppTheme.body(size: 12, color: AppTheme.muted),
                  ),
                ),
              ),
            ] else ...[
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: historyEvents.length,
                separatorBuilder: (ctx, i) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final ev = historyEvents[i];
                  final type = ev['type'] as String;
                  final time = ev['time'] as String;
                  final duration = ev['duration'] as String;
                  final icon = ev['icon'] as IconData;

                  return NeoCard(
                    backgroundColor: AppTheme.white,
                    shadowColor: AppTheme.ink900,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppTheme.paper,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppTheme.ink900, width: 1),
                              ),
                              child: Icon(icon, size: 16, color: AppTheme.ink900),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(type, style: AppTheme.bodyBold(size: 13, color: AppTheme.ink900)),
                                const SizedBox(height: 1),
                                Text(time, style: AppTheme.mono(size: 10, color: AppTheme.muted)),
                              ],
                            ),
                          ],
                        ),
                        Text(
                          duration,
                          style: AppTheme.mono(size: 12, color: AppTheme.ink900),
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
