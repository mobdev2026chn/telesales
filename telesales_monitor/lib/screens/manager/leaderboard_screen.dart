import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  int _timeFilter = 0; // 0 = TODAY, 1 = WEEK, 2 = MONTH
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);

    final callerName = tele.callerName.isNotEmpty ? tele.callerName.toUpperCase() : 'RASMI DESAI';

    // Callers list dataset built dynamically from Provider employees
    final List<Map<String, dynamic>> callers = [];

    int r = 1;
    for (var emp in tele.employees) {
      callers.add({
        'rank': r,
        'name': emp.name,
        'calls': emp.totalCalls,
        'connected': emp.connectedCalls,
        'talkTime': emp.talkTimeFormatted.isNotEmpty ? emp.talkTimeFormatted : '0s',
        'isCrown': r == 1,
      });
      r++;
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
            const SizedBox(height: 14),

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
                  hintText: 'Search caller...',
                  hintStyle: TextStyle(color: AppTheme.muted, fontSize: 13),
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.search, size: 18, color: AppTheme.ink900),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Filters Row (TODAY, WEEK, MONTH, TOP FIRST)
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
                        _buildFilterTab('TODAY', 0),
                        _buildFilterTab('WEEK', 1),
                        _buildFilterTab('MONTH', 2),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppTheme.ink900, width: 1.2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_drop_down, size: 16, color: AppTheme.ink900),
                      Text(
                        'TOP FIRST',
                        style: AppTheme.label(size: 8.5, color: AppTheme.ink900),
                      ),
                    ],
                  ),
                ),
              ],
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
                          width: 36,
                          child: Text(
                            rank < 10 ? '0$rank' : '$rank',
                            style: AppTheme.headline(
                              size: 26,
                              color: isTop ? AppTheme.greenNeon : AppTheme.ink900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

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
                                '$calls calls - $connected connected',
                                style: AppTheme.body(
                                  size: 11,
                                  color: isTop ? AppTheme.lightMuted : AppTheme.muted,
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

  Widget _buildFilterTab(String label, int index) {
    final isSelected = _timeFilter == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _timeFilter = index),
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
