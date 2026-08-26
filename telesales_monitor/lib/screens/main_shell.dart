import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/tele_provider.dart';
import 'manager/manager_dashboard.dart';
import 'manager/leaderboard_screen.dart';
import 'manager/employee_detail_screen.dart';
import 'caller/caller_dashboard.dart';
import 'caller/caller_history_screen.dart';
import 'caller/scheduled_callbacks_screen.dart';
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
    final isManager = tele.currentRole == UserRole.manager;
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
          bodyWidget = const CallerHistoryScreen();
          break;
        case 2:
          bodyWidget = const LeadsScreen();
          break;
        case 3:
          bodyWidget = const ScheduledCallbacksScreen();
          break;
        case 4:
          bodyWidget = const CallerProfileScreen();
          break;
        default:
          bodyWidget = const CallerHistoryScreen();
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
                // Main View Area
                Expanded(
                  child: bodyWidget,
                ),

                // Dark Bottom Navigation Bar
                Container(
                  decoration: const BoxDecoration(
                    color: AppTheme.ink900,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: isManager
                        ? [
                            _NavItem(icon: Icons.grid_view_outlined, label: 'DASHBOARD', index: 0, isSelected: tele.activeTabIndex == 0),
                            _NavItem(icon: Icons.menu, label: 'BOARD', index: 1, isSelected: tele.activeTabIndex == 1),
                            _NavItem(icon: Icons.radio_button_unchecked, label: 'LEADS', index: 2, isSelected: tele.activeTabIndex == 2),
                            _NavItem(icon: Icons.play_arrow, label: 'RECORDINGS', index: 3, isSelected: tele.activeTabIndex == 3),
                            _NavItem(icon: Icons.more_horiz, label: 'MORE', index: 4, isSelected: tele.activeTabIndex == 4),
                          ]
                        : [
                            _NavItem(icon: Icons.grid_view_outlined, label: 'MY DAY', index: 0, isSelected: tele.activeTabIndex == 0),
                            _NavItem(icon: Icons.phone, label: 'CALLS', index: 1, isSelected: tele.activeTabIndex == 1),
                            _NavItem(icon: Icons.radio_button_unchecked, label: 'MY LEADS', index: 2, isSelected: tele.activeTabIndex == 2),
                            _NavItem(icon: Icons.access_time, label: 'FOLLOW-UP', index: 3, isSelected: tele.activeTabIndex == 3),
                            _NavItem(icon: Icons.person_pin_outlined, label: 'PROFILE', index: 4, isSelected: tele.activeTabIndex == 4),
                          ],
                  ),
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

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final bool isSelected;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context, listen: false);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        tele.selectEmployee(null);
        tele.setTabIndex(index);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? AppTheme.greenNeon : AppTheme.muted,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: AppTheme.label(
                size: 8,
                color: isSelected ? AppTheme.limeYellow : AppTheme.muted,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
