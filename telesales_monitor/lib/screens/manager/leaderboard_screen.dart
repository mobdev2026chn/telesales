import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../widgets/top_header.dart';
import '../../providers/tele_provider.dart';
import '../../models/employee_model.dart';

class LeaderboardScreen extends StatefulWidget {
  final Function(EmployeeModel) onSelectEmployee;
  const LeaderboardScreen({super.key, required this.onSelectEmployee});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);

    final callerName = tele.currentUserName.toUpperCase();

    // Callers list dataset built dynamically from Provider employees
    final List<Map<String, dynamic>> callers = [];

    int r = 1;
    for (var emp in tele.employees) {
      if (emp.role.toLowerCase() == 'caller') {
        final calls = emp.totalCalls;
        final conn = emp.connectedCalls;
        final rate = calls > 0 ? ((conn / calls) * 100).toStringAsFixed(0) : '0';
        final progress = calls > 0 ? (calls / 100).clamp(0.01, 1.0) : 0.0;

        final isMe = emp.name.toLowerCase() == tele.callerName.toLowerCase() ||
                     emp.phone == tele.verifiedTrackingNumber;
        final photo = isMe && tele.profilePhotoBase64.isNotEmpty ? tele.profilePhotoBase64 : emp.photoBase64;

        callers.add({
          'rank': r,
          'name': emp.name,
          'calls': calls,
          'connected': conn,
          'connectRate': rate,
          'targetProgress': progress,
          'talkTime': emp.talkTimeFormatted.isNotEmpty ? emp.talkTimeFormatted : '0s',
          'isCrown': r == 1,
          'photoBase64': photo,
          'avatarUrl': emp.avatarUrl,
          'rawEmp': emp,
        });
        r++;
      }
    }

    final query = _searchCtrl.text.trim().toLowerCase();
    final filteredCallers = callers.where((c) {
      final name = (c['name'] as String).toLowerCase();
      return query.isEmpty || name.contains(query);
    }).toList();

    final isSearching = query.isNotEmpty;
    final hasTop3 = callers.length >= 3;

    final rank1 = hasTop3 ? callers[0] : null;
    final rank2 = hasTop3 ? callers[1] : null;
    final rank3 = hasTop3 ? callers[2] : null;

    final restOfCallers = (isSearching || !hasTop3)
        ? filteredCallers
        : callers.sublist(3);

    String calendarHeaderLabel = '📅 TODAY';
    if (tele.selectedDateRange != null) {
      calendarHeaderLabel = '📅 ${DateFormat('d MMM').format(tele.selectedDateRange!.start)} - ${DateFormat('d MMM').format(tele.selectedDateRange!.end)}'.toUpperCase();
    } else if (tele.selectedCustomDate != null) {
      calendarHeaderLabel = '📅 ${DateFormat('d MMM yyyy').format(tele.selectedCustomDate!).toUpperCase()}';
    } else if (tele.selectedTimeFilter == 1) {
      calendarHeaderLabel = '📅 THIS WEEK';
    } else if (tele.selectedTimeFilter == 2) {
      calendarHeaderLabel = '📅 THIS MONTH';
    }

    final hasCustomCalendar = tele.selectedDateRange != null || tele.selectedCustomDate != null;

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
              title: 'LEADERBOARD',
              userName: callerName,
              selectedSimIndex: 1,
            ),
            const SizedBox(height: 12),

            // Period Tabs: TODAY | WEEK | MONTH
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppTheme.ink900, width: 1.5),
                boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
              ),
              child: Row(
                children: [
                  _buildFilterTab(tele, 'TODAY', 0),
                  _buildFilterTab(tele, 'WEEK', 1),
                  _buildFilterTab(tele, 'MONTH', 2),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Interactive Calendar Picker Banner
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => _showCalendarPicker(context, tele),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: hasCustomCalendar ? AppTheme.limeYellow : AppTheme.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppTheme.ink900, width: 1.5),
                      boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_month_rounded, size: 16, color: AppTheme.ink900),
                        const SizedBox(width: 6),
                        Text(
                          calendarHeaderLabel,
                          style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.12),
                        ),
                        if (hasCustomCalendar) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              tele.setCustomDate(null);
                              tele.setDateRange(null);
                            },
                            child: const Icon(Icons.cancel_rounded, size: 16, color: AppTheme.ink900),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Text(
                  '${callers.length} AGENTS RANKED',
                  style: AppTheme.label(size: 9.5, color: AppTheme.muted, letterSpacing: 0.1),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Search Bar Input
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppTheme.ink900, width: 1.5),
                boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                style: AppTheme.body(size: 13, color: AppTheme.ink900),
                decoration: const InputDecoration(
                  hintText: 'Search caller by name...',
                  hintStyle: TextStyle(color: AppTheme.muted, fontSize: 13),
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.search, size: 18, color: AppTheme.ink900),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // TOP 3 PODIUM SECTION (Only when not searching & at least 3 callers)
            if (!isSearching && hasTop3) ...[
              Row(
                children: [
                  Container(width: 8, height: 8, color: AppTheme.greenNeon),
                  const SizedBox(width: 8),
                  Text(
                    'TOP PERFORMERS · PODIUM',
                    style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.18),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              _buildPodium(rank1!, rank2!, rank3!),
              const SizedBox(height: 14),
            ],

            // Section Subheader: ALL CALLERS / REST OF TEAM
            Row(
              children: [
                Container(width: 8, height: 8, color: AppTheme.greenNeon),
                const SizedBox(width: 8),
                Text(
                  isSearching ? 'SEARCH RESULTS' : 'RANKINGS · TALK TIME',
                  style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.18),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Ranked Caller List
            if (restOfCallers.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.all(30),
                child: Center(
                  child: Text(
                    'No callers found.',
                    style: AppTheme.body(size: 12, color: AppTheme.muted),
                  ),
                ),
              ),
            ] else ...[
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: restOfCallers.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final empData = restOfCallers[index];
                  final rank = empData['rank'] as int;
                  final name = empData['name'] as String;
                  final calls = empData['calls'] as int;
                  final connected = empData['connected'] as int;
                  final talkTime = empData['talkTime'] as String;
                  final isCrown = empData['isCrown'] as bool;
                  final isTop = rank == 1;

                  return NeoCard(
                    backgroundColor: isTop ? AppTheme.ink900 : AppTheme.white,
                    shadowColor: AppTheme.ink900,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    onTap: () {},
                    child: Row(
                      children: [
                        // Rank Digit
                        SizedBox(
                          width: 34,
                          child: Text(
                            rank < 10 ? '0$rank' : '$rank',
                            style: AppTheme.headline(
                              size: 24,
                              color: isTop ? AppTheme.greenNeon : AppTheme.ink900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Agent Profile Photo Avatar
                        _buildAgentAvatar(
                          name: name,
                          photoBase64: empData['photoBase64'] as String?,
                          avatarUrl: empData['avatarUrl'] as String?,
                          size: 40,
                          isDark: isTop,
                        ),
                        const SizedBox(width: 12),

                        // Caller Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (isCrown) ...[
                                    const Text('👑 ', style: TextStyle(fontSize: 14)),
                                  ],
                                  Flexible(
                                    child: Text(
                                      name,
                                      style: AppTheme.bodyBold(
                                        size: 14,
                                        color: isTop ? AppTheme.white : AppTheme.ink900,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$calls/100 calls (${empData['connectRate']}% conn) · $connected conn',
                                style: AppTheme.body(
                                  size: 11,
                                  color: isTop ? AppTheme.lightMuted : AppTheme.muted,
                                ),
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: Container(
                                  height: 4,
                                  width: 120,
                                  color: isTop ? AppTheme.ink800 : AppTheme.paper,
                                  child: FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: (empData['targetProgress'] as double? ?? 0.0),
                                    child: Container(color: isTop ? AppTheme.limeYellow : AppTheme.greenNeon),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Talk Time Stat
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              talkTime,
                              style: AppTheme.mono(
                                size: 15,
                                color: isTop ? AppTheme.white : AppTheme.ink900,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              'TALK TIME',
                              style: AppTheme.label(
                                size: 8,
                                color: isTop ? AppTheme.lightMuted : AppTheme.muted,
                                letterSpacing: 0.12,
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

  // AGENT AVATAR HELPER WIDGET
  Widget _buildAgentAvatar({
    required String name,
    String? photoBase64,
    String? avatarUrl,
    double size = 42,
    bool isDark = false,
    bool showBorder = true,
  }) {
    ImageProvider? imageProvider;
    if (photoBase64 != null && photoBase64.isNotEmpty) {
      if (photoBase64.startsWith('/') || photoBase64.contains(':\\')) {
        final f = File(photoBase64);
        if (f.existsSync()) {
          imageProvider = FileImage(f);
        }
      } else {
        try {
          final cleanBase64 = photoBase64.contains(',') ? photoBase64.split(',').last : photoBase64;
          final bytes = base64Decode(cleanBase64);
          imageProvider = MemoryImage(bytes);
        } catch (_) {}
      }
    }
    if (imageProvider == null && avatarUrl != null && avatarUrl.isNotEmpty) {
      imageProvider = NetworkImage(avatarUrl);
    }

    final initials = name.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join('').toUpperCase();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.ink800 : AppTheme.paper,
        shape: BoxShape.circle,
        border: showBorder ? Border.all(color: isDark ? AppTheme.limeYellow : AppTheme.ink900, width: 1.5) : null,
        boxShadow: showBorder ? AppTheme.neoShadowSm(color: AppTheme.ink900) : null,
        image: imageProvider != null
            ? DecorationImage(image: imageProvider, fit: BoxFit.cover)
            : null,
      ),
      child: imageProvider == null
          ? Center(
              child: Text(
                initials.isNotEmpty ? initials : '👤',
                style: AppTheme.headline(
                  size: size * 0.38,
                  color: isDark ? AppTheme.limeYellow : AppTheme.ink900,
                ),
              ),
            )
          : null,
    );
  }

  // PODIUM LAYOUT WIDGET (Rank 2 on Left, Rank 1 in Center, Rank 3 on Right)
  Widget _buildPodium(Map<String, dynamic> r1, Map<String, dynamic> r2, Map<String, dynamic> r3) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Rank 2 (Left - Silver)
        Expanded(
          child: _buildPodiumStep(
            rankData: r2,
            rankNum: 2,
            stepHeight: 120,
            badgeLabel: '2ND · SILVER',
            badgeBg: const Color(0xFF64748B),
            isDark: false,
          ),
        ),
        const SizedBox(width: 8),

        // Rank 1 (Center - Gold 👑 Taller)
        Expanded(
          child: _buildPodiumStep(
            rankData: r1,
            rankNum: 1,
            stepHeight: 160,
            badgeLabel: '1ST · GOLD 👑',
            badgeBg: AppTheme.greenNeon,
            isDark: true,
          ),
        ),
        const SizedBox(width: 8),

        // Rank 3 (Right - Bronze)
        Expanded(
          child: _buildPodiumStep(
            rankData: r3,
            rankNum: 3,
            stepHeight: 100,
            badgeLabel: '3RD · BRONZE',
            badgeBg: const Color(0xFFD97706),
            isDark: false,
          ),
        ),
      ],
    );
  }

  Widget _buildPodiumStep({
    required Map<String, dynamic> rankData,
    required int rankNum,
    required double stepHeight,
    required String badgeLabel,
    required Color badgeBg,
    required bool isDark,
  }) {
    final name = rankData['name'] as String;
    final talkTime = rankData['talkTime'] as String;
    final calls = rankData['calls'] as int;
    final photoBase64 = rankData['photoBase64'] as String?;
    final avatarUrl = rankData['avatarUrl'] as String?;

    final shortName = name.split(' ').first;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Crown Icon for Rank 1
        if (rankNum == 1) ...[
          const Text('👑', style: TextStyle(fontSize: 22)),
          const SizedBox(height: 4),
        ] else ...[
          const SizedBox(height: 12),
        ],

        // Agent Profile Photo Avatar on Podium
        _buildAgentAvatar(
          name: name,
          photoBase64: photoBase64,
          avatarUrl: avatarUrl,
          size: rankNum == 1 ? 52 : 44,
          isDark: isDark,
        ),
        const SizedBox(height: 6),

        // Name Tag above step
        Text(
          shortName,
          style: AppTheme.bodyBold(size: 13, color: AppTheme.ink900),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          talkTime,
          style: AppTheme.mono(size: 11, color: isDark ? AppTheme.greenDark : AppTheme.muted),
        ),
        const SizedBox(height: 8),

        // Podium Block Step
        NeoCard(
          backgroundColor: isDark ? AppTheme.ink900 : AppTheme.white,
          shadowColor: AppTheme.ink900,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Container(
            height: stepHeight,
            width: double.infinity,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Rank Badge Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppTheme.ink900, width: 1),
                  ),
                  child: Text(
                    badgeLabel,
                    style: AppTheme.label(
                      size: 8,
                      color: isDark ? AppTheme.ink900 : AppTheme.white,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Large Rank Number
                Text(
                  '#$rankNum',
                  style: AppTheme.headline(
                    size: rankNum == 1 ? 36 : 28,
                    color: isDark ? AppTheme.limeYellow : AppTheme.ink900,
                  ),
                ),
                const SizedBox(height: 4),

                Text(
                  '$calls calls',
                  style: AppTheme.body(
                    size: 10,
                    color: isDark ? AppTheme.lightMuted : AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterTab(TeleProvider tele, String label, int index) {
    final isSelected = tele.selectedTimeFilter == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => tele.setTimeFilter(index),
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

  Future<void> _showCalendarPicker(BuildContext context, TeleProvider tele) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppTheme.paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppTheme.ink900, width: 2),
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
            Text('FILTER LEADERBOARD BY DATE', style: AppTheme.headline(size: 16, color: AppTheme.ink900)),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.event, color: AppTheme.ink900),
              title: Text('Select Specific Date', style: AppTheme.bodyBold(size: 14)),
              subtitle: Text('View standings for a single specific day', style: AppTheme.body(size: 12, color: AppTheme.muted)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.ink900, width: 1.5),
              ),
              tileColor: AppTheme.white,
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await showDatePicker(
                  context: context,
                  initialDate: tele.selectedCustomDate ?? DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now(),
                  builder: (c, child) => Theme(
                    data: Theme.of(c).copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: AppTheme.ink900,
                        onPrimary: AppTheme.limeYellow,
                        surface: AppTheme.paper,
                        onSurface: AppTheme.ink900,
                      ),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) tele.setCustomDate(picked);
              },
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.date_range, color: AppTheme.ink900),
              title: Text('Select Date Range', style: AppTheme.bodyBold(size: 14)),
              subtitle: Text('View standings across a custom period', style: AppTheme.body(size: 12, color: AppTheme.muted)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.ink900, width: 1.5),
              ),
              tileColor: AppTheme.white,
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now(),
                  initialDateRange: tele.selectedDateRange ?? DateTimeRange(
                    start: DateTime.now().subtract(const Duration(days: 7)),
                    end: DateTime.now(),
                  ),
                  builder: (c, child) => Theme(
                    data: Theme.of(c).copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: AppTheme.ink900,
                        onPrimary: AppTheme.limeYellow,
                        surface: AppTheme.paper,
                        onSurface: AppTheme.ink900,
                      ),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) tele.setDateRange(picked);
              },
            ),
          ],
        ),
      ),
    );
  }
}
