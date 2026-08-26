import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../widgets/neo_button.dart';
import '../../providers/tele_provider.dart';
import '../../models/employee_model.dart';

class LeaderboardScreen extends StatelessWidget {
  final Function(EmployeeModel) onSelectEmployee;
  const LeaderboardScreen({super.key, required this.onSelectEmployee});

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);
    final currentDateStr = DateFormat('d MMM yyyy').format(DateTime.now()).toUpperCase();
    final employees = tele.employees;

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
                          'LEADERBOARD',
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
                        'MANAGER',
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

            // Ranked by Talk Time indicator
            Row(
              children: [
                Container(width: 8, height: 8, color: AppTheme.greenNeon),
                const SizedBox(width: 8),
                Text(
                  'RANKED BY TALK TIME · TODAY',
                  style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.18),
                ),
              ],
            ),
            // Ranked List
            if (employees.isEmpty)
              NeoCard(
                backgroundColor: AppTheme.white,
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.people_outline, size: 36, color: AppTheme.muted),
                      const SizedBox(height: 10),
                      Text(
                        'No callers logged in database yet.',
                        style: AppTheme.bodyBold(size: 14, color: AppTheme.ink900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Start dialing calls to build real-time team ranking.',
                        style: AppTheme.body(size: 12, color: AppTheme.muted),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: employees.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final emp = employees[index];
                  final isTop = emp.rank == 1;

                return NeoCard(
                  backgroundColor: isTop ? AppTheme.ink900 : AppTheme.white,
                  shadowColor: isTop ? AppTheme.ink900 : AppTheme.ink900,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  onTap: () => onSelectEmployee(emp),
                  child: Row(
                    children: [
                      // Rank Digit
                      SizedBox(
                        width: 42,
                        child: Text(
                          emp.rank < 10 ? '0${emp.rank}' : '${emp.rank}',
                          style: AppTheme.headline(
                            size: 28,
                            color: AppTheme.greenNeon,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Caller Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              emp.name,
                              style: AppTheme.bodyBold(
                                size: 14,
                                color: isTop ? AppTheme.white : AppTheme.ink900,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${emp.totalCalls} calls · ${emp.connectedCalls} connected',
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
                            emp.talkTimeFormatted,
                            style: AppTheme.mono(
                              size: 14,
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
        ),
      ),
    );
  }
}
