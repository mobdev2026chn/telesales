import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:antd_icons_flutter/antd_icons_flutter.dart';
import '../theme/app_theme.dart';
import '../providers/tele_provider.dart';
import '../widgets/work_sim_picker.dart';
import 'manager/manager_dashboard.dart';
import 'manager/leaderboard_screen.dart';
import 'manager/employee_detail_screen.dart';
import 'caller/caller_dashboard.dart';
import 'caller/dialer_screen.dart';
// import 'caller/caller_stats_screen.dart';
import 'caller/caller_profile_screen.dart';
import 'caller/book_demo_screen.dart';
import 'login_screen.dart';
import 'shared/leads_screen.dart';
import 'shared/recordings_screen.dart';
import 'shared/more_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  bool _simPromptOpen = false;

  /// Signed-in caller or Team Leader on a dual-SIM phone whose work SIM is unknown: ask which SIM
  /// holds the registered number, so calls on the other SIM are never tracked.
  void _maybeAskWorkSim(TeleProvider tele) {
    if (!tele.needsWorkSimChoice || _simPromptOpen) return;
    _simPromptOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final slot = await showWorkSimPicker(context, sims: tele.detectedSims, registeredPhone: tele.verifiedTrackingNumber);
      if (slot != null) {
        await tele.setWorkSimForRegisteredNumber(slot);
        _simPromptOpen = false;
      }
      // Closed without a choice: not asked again until the app is opened next time
    });
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);
    if (!tele.isLoggedIn) {
      return const LoginScreen();
    }
    _maybeAskWorkSim(tele);
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
        case 5:
          bodyWidget = const DialerScreen();
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
          bodyWidget = const DialerScreen();
          break;
        case 3:
          bodyWidget = const BookDemoScreen();
          break;
        case 4:
          bodyWidget = const CallerProfileScreen();
          break;
        default:
          bodyWidget = const CallerDashboard();
      }
    }

    final List<_FooterDestination> footerDestinations = isManager
        ? const [
            _FooterDestination('DASHBOARD', 0, AntIcons.dashboardOutlined),
            _FooterDestination('BOARD', 1, AntIcons.teamOutlined),
            _FooterDestination('LEADS', 2, AntIcons.solutionOutlined),
            _FooterDestination('RECS', 3, AntIcons.fileTextOutlined),
          ]
        : const [
            _FooterDestination('HOME', 0, AntIcons.homeOutlined),
            _FooterDestination('LEADS', 1, AntIcons.solutionOutlined),
            _FooterDestination('BOOK DEMO', 3, AntIcons.calendarOutlined),
            _FooterDestination('PROFILE', 4, AntIcons.userOutlined),
          ];
    final dialerIndex = isManager ? 5 : 2;
    final footerSplitIndex = footerDestinations.length ~/ 2;

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
                      top: BorderSide(
                        color: AppTheme.ink900.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      height: 68,
                      child: Row(
                        children: [
                          Expanded(
                            child: _FooterDestinationGroup(
                              destinations: footerDestinations
                                  .take(footerSplitIndex)
                                  .toList(),
                              activeIndex: tele.activeTabIndex,
                              onSelected: (index) {
                                tele.selectEmployee(null);
                                tele.setTabIndex(index);
                              },
                            ),
                          ),
                          _FooterDialerButton(
                            isSelected: tele.activeTabIndex == dialerIndex,
                            onTap: () {
                              tele.selectEmployee(null);
                              tele.setTabIndex(dialerIndex);
                            },
                          ),
                          Expanded(
                            child: _FooterDestinationGroup(
                              destinations: footerDestinations
                                  .skip(footerSplitIndex)
                                  .toList(),
                              activeIndex: tele.activeTabIndex,
                              onSelected: (index) {
                                tele.selectEmployee(null);
                                tele.setTabIndex(index);
                              },
                            ),
                          ),
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

class _FooterDestination {
  final String label;
  final int index;
  final IconData icon;

  const _FooterDestination(this.label, this.index, this.icon);
}

class _FooterDestinationGroup extends StatelessWidget {
  final List<_FooterDestination> destinations;
  final int activeIndex;
  final ValueChanged<int> onSelected;

  const _FooterDestinationGroup({
    required this.destinations,
    required this.activeIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: destinations
          .map(
            (destination) => Expanded(
              child: _FooterDestinationButton(
                destination: destination,
                isSelected: activeIndex == destination.index,
                onTap: () => onSelected(destination.index),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _FooterDestinationButton extends StatelessWidget {
  final _FooterDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  const _FooterDestinationButton({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppTheme.greenDark : AppTheme.ink700;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(destination.icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(
            destination.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.label(size: 8.5, color: color),
          ),
        ],
      ),
    );
  }
}

class _FooterDialerButton extends StatefulWidget {
  final bool isSelected;
  final VoidCallback onTap;

  const _FooterDialerButton({required this.isSelected, required this.onTap});

  @override
  State<_FooterDialerButton> createState() => _FooterDialerButtonState();
}

class _FooterDialerButtonState extends State<_FooterDialerButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  late final Animation<double> _scale = Tween<double>(begin: 0.96, end: 1.04)
      .animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutSine),
      );

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labelColor = widget.isSelected
        ? AppTheme.greenDark
        : AppTheme.ink700;
    return SizedBox(
      width: 68,
      height: 68,
      child: Semantics(
        button: true,
        label: 'Open dialer',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.translate(
                offset: const Offset(0, -8),
                child: ScaleTransition(
                  scale: _scale,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.greenNeon,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.ink900.withValues(alpha: 0.2),
                          blurRadius: 7,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.dialpad_rounded,
                      size: 22,
                      color: AppTheme.ink900,
                    ),
                  ),
                ),
              ),
              Text(
                'DIALER',
                maxLines: 1,
                style: AppTheme.label(size: 8.5, color: labelColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
