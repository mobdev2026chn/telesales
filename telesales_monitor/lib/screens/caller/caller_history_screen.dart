import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../widgets/top_header.dart';
import '../../widgets/dialer_pad_sheet.dart';
import '../../widgets/contact_history_sheet.dart';
import '../../widgets/advanced_filter_sheet.dart';
import '../../widgets/save_contact_dialog.dart';
import '../../providers/tele_provider.dart';
import '../../models/call_log_model.dart';

class CallerHistoryScreen extends StatefulWidget {
  const CallerHistoryScreen({super.key});

  @override
  State<CallerHistoryScreen> createState() => _CallerHistoryScreenState();
}

class _CallerHistoryScreenState extends State<CallerHistoryScreen> {
  int _selectedFilterTab = 1; // 0 = ALL CALLS, 1 = UNIQUE, 2 = FILTER

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);

    final callerName = tele.callerName.isNotEmpty ? tele.callerName.toUpperCase() : 'CALLER AGENT';
    final activeLogs = tele.filteredCallLogs;

    // Grouping call logs by phone number for Unique View
    final Map<String, List<CallLogModel>> groupedByPhone = {};
    for (var c in activeLogs) {
      if (c.phoneNumber.isNotEmpty) {
        groupedByPhone.putIfAbsent(c.phoneNumber, () => []).add(c);
      }
    }

    final uniqueCount = groupedByPhone.length;
    int calledOnceCount = 0;
    int multipleCount = 0;

    groupedByPhone.forEach((phone, list) {
      if (list.length == 1) {
        calledOnceCount++;
      } else {
        multipleCount++;
      }
    });

    // Build dynamic display list strictly from actual phone call logs
    final List<Map<String, dynamic>> displayItems = [];

    groupedByPhone.forEach((phone, list) {
      final first = list.first;
      final count = list.length;
      final totalSeconds = list.fold(0, (sum, item) => sum + item.duration.inSeconds);
      final mins = totalSeconds ~/ 60;
      final secs = totalSeconds % 60;
      final timeStr = totalSeconds > 0 ? '${mins}m ${secs}s total' : '0s total';

      displayItems.add({
        'name': first.contactName != 'Unknown' ? first.contactName : phone,
        'phone': phone,
        'badge': count > 1 ? '×$count TODAY' : 'ONCE',
        'totalTime': timeStr,
        'badgeStyle': count > 1 ? 'lime' : 'outline',
        'rawLogs': list,
      });
    });

    return Scaffold(
      backgroundColor: AppTheme.paper,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 24, right: 8),
        child: GestureDetector(
          onTap: () => DialerPadSheet.show(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.greenNeon,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppTheme.ink900, width: 1.5),
              boxShadow: AppTheme.neoShadow(color: AppTheme.ink900, offset: 4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.phone, size: 16, color: AppTheme.ink900),
                const SizedBox(width: 6),
                Text(
                  'DIAL',
                  style: AppTheme.label(size: 11, color: AppTheme.ink900, letterSpacing: 0.12),
                ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppTheme.greenNeon,
        backgroundColor: AppTheme.ink900,
        onRefresh: () async {
          await tele.fetchDeviceCallLogs();
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
                title: 'CALL HISTORY',
                userName: callerName,
                selectedSimIndex: 1,
              ),
              const SizedBox(height: 14),

              // Filter Tabs (ALL CALLS | UNIQUE | FILTER)
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: AppTheme.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppTheme.ink900, width: 1.2),
                      ),
                      child: Row(
                        children: [
                          _buildFilterTab('ALL CALLS', 0),
                          _buildFilterTab('UNIQUE', 1),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      setState(() => _selectedFilterTab = 2);
                      AdvancedFilterSheet.show(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _selectedFilterTab == 2 ? AppTheme.ink900 : AppTheme.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppTheme.ink900, width: 1.2),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            size: 14,
                            color: _selectedFilterTab == 2 ? AppTheme.limeYellow : AppTheme.ink900,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'FILTER',
                            style: AppTheme.label(
                              size: 8.5,
                              color: _selectedFilterTab == 2 ? AppTheme.limeYellow : AppTheme.ink900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Header Summary Card (#10180C)
              NeoCard(
                backgroundColor: AppTheme.ink900,
                shadowColor: AppTheme.ink900,
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text('$uniqueCount', style: AppTheme.headline(size: 28, color: AppTheme.white)),
                        const SizedBox(height: 2),
                        Text('UNIQUE NUMBERS', style: AppTheme.label(size: 8, color: AppTheme.lightMuted)),
                      ],
                    ),
                    Column(
                      children: [
                        Text('$calledOnceCount', style: AppTheme.headline(size: 28, color: AppTheme.limeYellow)),
                        const SizedBox(height: 2),
                        Text('CALLED ONCE', style: AppTheme.label(size: 8, color: AppTheme.lightMuted)),
                      ],
                    ),
                    Column(
                      children: [
                        Text('$multipleCount', style: AppTheme.headline(size: 28, color: AppTheme.limeYellow)),
                        const SizedBox(height: 2),
                        Text('MULTIPLE', style: AppTheme.label(size: 8, color: AppTheme.lightMuted)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Call History Items List
              if (displayItems.isEmpty) ...[
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(Icons.phone_missed, size: 44, color: AppTheme.muted),
                        const SizedBox(height: 10),
                        Text('NO LOGGED CALLS YET', style: AppTheme.headline(size: 18)),
                        const SizedBox(height: 4),
                        Text(
                          'Make or receive phone calls to view call history.',
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
                  itemCount: displayItems.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final item = displayItems[i];
                    final name = item['name'] as String;
                    final phone = item['phone'] as String;
                    final badge = item['badge'] as String;
                    final totalTime = item['totalTime'] as String;
                    final badgeStyle = item['badgeStyle'] as String;

                    final isLime = badgeStyle == 'lime';

                    final isUnsaved = name == phone || name == 'Unknown';

                    return NeoCard(
                      backgroundColor: AppTheme.white,
                      shadowColor: AppTheme.ink900,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      onTap: () => ContactHistorySheet.show(context, item),
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
                                  color: isLime ? AppTheme.greenGrass : AppTheme.white,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: AppTheme.ink900, width: 1),
                                ),
                                child: Text(
                                  badge,
                                  style: AppTheme.label(size: 8.5, color: AppTheme.ink900),
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
                                totalTime,
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
      ),
    );
  }

  Widget _buildFilterTab(String label, int index) {
    final isSelected = _selectedFilterTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedFilterTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.ink900 : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            child: Text(
              label,
              style: AppTheme.label(
                size: 9,
                color: isSelected ? AppTheme.limeYellow : AppTheme.ink900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
