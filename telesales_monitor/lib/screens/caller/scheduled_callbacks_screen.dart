import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../widgets/neo_button.dart';
import '../../widgets/top_header.dart';
import '../../widgets/reschedule_sheet.dart';
import '../../widgets/save_contact_dialog.dart';
import '../../providers/tele_provider.dart';

class ScheduledCallbacksScreen extends StatefulWidget {
  const ScheduledCallbacksScreen({super.key});

  @override
  State<ScheduledCallbacksScreen> createState() => _ScheduledCallbacksScreenState();
}

class _ScheduledCallbacksScreenState extends State<ScheduledCallbacksScreen> {
  int _selectedFilterIndex = 0; // 0 = ALL, 1 = TODAY, 2 = TOMORROW, 3 = WEEK, 4 = MONTH

  final List<String> _filterOpts = ['ALL', 'TODAY', 'TOMORROW', 'WEEK', 'MONTH'];

  String _formatScheduleTime(DateTime dt) {
    final now = DateTime.now();
    final diff = dt.difference(now);
    if (diff.inHours >= 0 && diff.inHours < 12 && dt.day == now.day) {
      return DateFormat('h:mm a').format(dt);
    }
    if (dt.day == now.day + 1) {
      return 'TOMORROW ${DateFormat('h a').format(dt)}';
    }
    return DateFormat('d MMM · h:mm a').format(dt).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);

    final callerName = tele.callerName.isNotEmpty ? tele.callerName.toUpperCase() : 'CALLER AGENT';
    final rawCallbacks = tele.callbacks;
    final now = DateTime.now();

    // Dynamic Filter
    final callbacksList = rawCallbacks.where((cb) {
      if (_selectedFilterIndex == 1) {
        // TODAY
        return cb.scheduledTime.year == now.year &&
            cb.scheduledTime.month == now.month &&
            cb.scheduledTime.day == now.day;
      } else if (_selectedFilterIndex == 2) {
        // TOMORROW
        final tom = now.add(const Duration(days: 1));
        return cb.scheduledTime.year == tom.year &&
            cb.scheduledTime.month == tom.month &&
            cb.scheduledTime.day == tom.day;
      } else if (_selectedFilterIndex == 3) {
        // WEEK
        final weekEnd = now.add(const Duration(days: 7));
        return cb.scheduledTime.isBefore(weekEnd);
      } else if (_selectedFilterIndex == 4) {
        // MONTH
        final monthEnd = now.add(const Duration(days: 30));
        return cb.scheduledTime.isBefore(monthEnd);
      }
      return true;
    }).toList();

    return RefreshIndicator(
      color: AppTheme.greenNeon,
      backgroundColor: AppTheme.ink900,
      onRefresh: () async {
        await tele.fetchBackendData();
        await tele.fetchDeviceCallLogs();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // Top Header Bar
          TopHeader(
            title: 'FOLLOW-UP',
            userName: callerName,
            selectedSimIndex: 1,
          ),
          const SizedBox(height: 14),

          // Subheader: FOLLOW-UP CALLS · N
          Row(
            children: [
              Container(width: 8, height: 8, color: AppTheme.greenNeon),
              const SizedBox(width: 8),
              Text(
                'FOLLOW-UP CALLS · ${callbacksList.length}',
                style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.18),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Filter Chips (ALL, TODAY, TOMORROW, WEEK, MONTH)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int index = 0; index < _filterOpts.length; index++) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedFilterIndex = index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: _selectedFilterIndex == index ? AppTheme.ink900 : AppTheme.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppTheme.ink900, width: 1.2),
                        ),
                        child: Text(
                          _filterOpts[index],
                          style: AppTheme.label(
                            size: 9,
                            color: _selectedFilterIndex == index ? AppTheme.limeYellow : AppTheme.ink900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Follow-up Cards List
          if (callbacksList.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 44, color: AppTheme.muted),
                    const SizedBox(height: 10),
                    Text('NO PENDING FOLLOW-UPS', style: AppTheme.headline(size: 18)),
                    const SizedBox(height: 4),
                    Text(
                      'All scheduled callbacks are completed or none found.',
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
              itemCount: callbacksList.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final cb = callbacksList[index];
                final isDark = index == 0;
                final timeStr = _formatScheduleTime(cb.scheduledTime);

                final cleanName = cb.name.replaceAll(RegExp(r'[\s+\-()]'), '');
                final cleanPhone = cb.phone.replaceAll(RegExp(r'[\s+\-()]'), '');
                final isUnsaved = cb.name.trim().isEmpty ||
                    cb.name == 'Unknown' ||
                    cb.name == 'Client' ||
                    cb.name == 'Unsaved' ||
                    cleanName == cleanPhone ||
                    cleanName.endsWith(cleanPhone) ||
                    cleanPhone.endsWith(cleanName) ||
                    RegExp(r'^\d+$').hasMatch(cleanName);

                return NeoCard(
                  backgroundColor: isDark ? AppTheme.ink900 : AppTheme.white,
                  shadowColor: AppTheme.ink900,
                  padding: const EdgeInsets.all(16),
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
                                    cb.name,
                                    style: AppTheme.bodyBold(
                                      size: 14,
                                      color: isDark ? AppTheme.white : AppTheme.ink900,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (cb.phone.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => SaveContactDialog.show(context, cb.phone, initialName: isUnsaved ? null : cb.name),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isUnsaved ? AppTheme.limeYellow : (isDark ? AppTheme.ink800 : AppTheme.paper),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: isDark ? AppTheme.limeYellow : AppTheme.ink900, width: 1),
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
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            timeStr,
                            style: AppTheme.mono(
                              size: 11,
                              color: isDark ? AppTheme.limeYellow : AppTheme.ink900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        cb.note,
                        style: AppTheme.body(
                          size: 11.5,
                          color: isDark ? AppTheme.lightMuted : AppTheme.muted,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Action Buttons (CALL NOW | RESCHEDULE)
                      Row(
                        children: [
                          Expanded(
                            child: NeoButton(
                              backgroundColor: AppTheme.limeYellow,
                              shadowColor: AppTheme.ink900,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              onTap: () => tele.launchCall(cb.phone),
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.phone, size: 14, color: AppTheme.ink900),
                                    const SizedBox(width: 6),
                                    Text(
                                      'CALL NOW',
                                      style: AppTheme.label(size: 9.5, color: AppTheme.ink900, letterSpacing: 0.1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => RescheduleSheet.show(context, contactName: cb.name, phone: cb.phone),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: isDark ? AppTheme.white : AppTheme.paper,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppTheme.ink900, width: 1.2),
                                ),
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.calendar_today, size: 13, color: AppTheme.ink900),
                                      const SizedBox(width: 6),
                                      Text(
                                        'RESCHEDULE',
                                        style: AppTheme.label(size: 9.5, color: AppTheme.ink900),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
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
