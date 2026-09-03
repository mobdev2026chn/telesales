import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/tele_provider.dart';
import 'manager/manager_dashboard.dart';
import 'manager/leaderboard_screen.dart';
import 'manager/employee_detail_screen.dart';
import 'caller/caller_dashboard.dart';
import 'caller/caller_history_screen.dart';
import 'caller/caller_profile_screen.dart';
import 'shared/leads_screen.dart';
import 'shared/recordings_screen.dart';
import 'shared/more_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);
    final isManager = tele.currentRole == UserRole.manager && !tele.isManagerCallerMode;
    final isEmpDetailOpen = tele.selectedEmployee != null;

    Widget bodyWidget;
    if (isEmpDetailOpen) {
      bodyWidget = EmployeeDetailScreen(
        employee: tele.selectedEmployee!,
        onBack: () => tele.selectEmployee(null),
      );
    } else if (isManager) {
      switch (tele.activeTabIndex) {
        case 0:
          bodyWidget = ManagerDashboard(onNavigateToBoard: () => tele.setTabIndex(1));
          break;
        case 1:
          bodyWidget = LeaderboardScreen(onSelectEmployee: (emp) => tele.selectEmployee(emp));
          break;
        case 2:
          bodyWidget = const LeadsScreen();
          break;
        case 3:
          bodyWidget = const RecordingsScreen();
          break;
        case 4:
          bodyWidget = MoreScreen(onNavigateToBoard: () => tele.setTabIndex(1));
          break;
        default:
          bodyWidget = ManagerDashboard(onNavigateToBoard: () => tele.setTabIndex(1));
      }
    } else {
      switch (tele.activeTabIndex) {
        case 0:
          bodyWidget = const CallerDashboard();
          break;
        case 1:
          bodyWidget = const LeadsScreen();
          break;
        case 2:
          bodyWidget = const CallerHistoryScreen();
          break;
        case 3:
          bodyWidget = const CallerProfileScreen();
          break;
        default:
          bodyWidget = const CallerDashboard();
      }
    }

    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Column(
              children: [
                if (tele.isManagerCallerMode)
                  Container(
                    width: double.infinity,
                    color: AppTheme.limeYellow,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.headset_mic_rounded, size: 16, color: AppTheme.ink900),
                            const SizedBox(width: 8),
                            Text(
                              'CALLER MODE ACTIVE (MANAGER)',
                              style: AppTheme.mono(size: 10, color: AppTheme.ink900, weight: FontWeight.w700),
                            ),
                          ],
                        ),
                        GestureDetector(
                          onTap: () => tele.toggleManagerCallerMode(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.ink900,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'EXIT TO MANAGER →',
                              style: AppTheme.mono(size: 9, color: AppTheme.limeYellow, weight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Main View Area
                Expanded(
                  child: bodyWidget,
                ),

                // Redesigned Modern Bottom Navigation Bar Matching Screenshots
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.white,
                    border: Border(
                      top: BorderSide(color: AppTheme.ink900, width: 1.5),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 52,
                          child: Row(
                            children: isManager
                                ? [
                                    _TabItem(label: 'DASHBOARD', index: 0, isSelected: tele.activeTabIndex == 0),
                                    _TabItem(label: 'BOARD', index: 1, isSelected: tele.activeTabIndex == 1),
                                    _TabItem(label: 'LEADS', index: 2, isSelected: tele.activeTabIndex == 2),
                                    _TabItem(label: 'RECS', index: 3, isSelected: tele.activeTabIndex == 3),
                                    _TabItem(label: 'MORE', index: 4, isSelected: tele.activeTabIndex == 4),
                                  ]
                                : [
                                    _TabItem(label: 'HOME', index: 0, isSelected: tele.activeTabIndex == 0),
                                    _TabItem(label: 'LEADS', index: 1, isSelected: tele.activeTabIndex == 1),
                                    _TabItem(label: 'STATS', index: 2, isSelected: tele.activeTabIndex == 2),
                                    _TabItem(label: 'PROFILE', index: 3, isSelected: tele.activeTabIndex == 3),
                                  ],
                          ),
                        ),
                        // Bottom Indicator Strip
                        Container(
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 6),
                          width: 130,
                          decoration: BoxDecoration(
                            color: AppTheme.ink900,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final String label;
  final int index;
  final bool isSelected;

  const _TabItem({
    required this.label,
    required this.index,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context, listen: false);

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          tele.selectEmployee(null);
          tele.setTabIndex(index);
        },
        child: Container(
          height: double.infinity,
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.limeYellow : AppTheme.white,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: AppTheme.mono(
                  size: 10.5,
                  color: isSelected ? AppTheme.ink900 : AppTheme.muted,
                  weight: isSelected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(height: 3),
                Container(
                  width: 32,
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: AppTheme.ink900,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
