import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../widgets/neo_card.dart';
import '../widgets/neo_button.dart';
import '../widgets/ticker_banner.dart';
import '../providers/tele_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  int _selectedTab = 0; // 0 = Manager / Admin, 1 = Caller / Agent
  final TextEditingController _adminEmailCtrl = TextEditingController(text: 'admin@askeva.com');
  final TextEditingController _adminPassCtrl = TextEditingController(text: '••••••••');
  bool _obscurePass = true;

  @override
  void dispose() {
    _adminEmailCtrl.dispose();
    _adminPassCtrl.dispose();
    super.dispose();
  }

  void _loginAsAdmin(TeleProvider tele) {
    tele.setRole(UserRole.manager);
  }

  void _loginAsCaller(TeleProvider tele) {
    tele.setRole(UserRole.caller);
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);

    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        Text(
                          'ASKEVA · TELEMONITOR',
                          style: AppTheme.label(size: 10, color: AppTheme.muted, letterSpacing: 0.18),
                        ),
                        const SizedBox(height: 14),
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: 'EVERY CALL\nIS A ',
                                style: AppTheme.headline(size: 44, color: AppTheme.ink900),
                              ),
                              TextSpan(
                                text: 'lead',
                                style: AppTheme.italicSerif(size: 42, color: AppTheme.greenDark),
                              ),
                              TextSpan(
                                text: '.',
                                style: AppTheme.headline(size: 44, color: AppTheme.greenNeon),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Real-time call monitoring, automated call recording and team analytics connected to MongoDB.',
                          style: AppTheme.body(size: 13, color: AppTheme.ink700),
                        ),
                        const SizedBox(height: 20),
                        const TickerBanner(),
                        const SizedBox(height: 24),

                        // Tab Switcher
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppTheme.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppTheme.ink900, width: 1.5),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() => _selectedTab = 0),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      color: _selectedTab == 0 ? AppTheme.ink900 : Colors.transparent,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'ADMIN LOGIN',
                                        style: AppTheme.label(
                                          size: 11,
                                          color: _selectedTab == 0 ? AppTheme.limeYellow : AppTheme.ink700,
                                          letterSpacing: 0.12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() => _selectedTab = 1),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      color: _selectedTab == 1 ? AppTheme.ink900 : Colors.transparent,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'CALLER AGENT',
                                        style: AppTheme.label(
                                          size: 11,
                                          color: _selectedTab == 1 ? AppTheme.greenNeon : AppTheme.ink700,
                                          letterSpacing: 0.12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Tab 0: Admin Login
                        if (_selectedTab == 0) ...[
                          NeoCard(
                            backgroundColor: AppTheme.white,
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'ADMINISTRATOR ACCESS',
                                      style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.16),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.limeYellow,
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(color: AppTheme.ink900, width: 1),
                                      ),
                                      child: Text(
                                        'MONGODB',
                                        style: AppTheme.label(size: 8, color: AppTheme.ink900),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text('EMAIL ADDRESS', style: AppTheme.label(size: 9, color: AppTheme.muted)),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.paper,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppTheme.ink900, width: 1.2),
                                  ),
                                  child: TextField(
                                    controller: _adminEmailCtrl,
                                    style: AppTheme.bodyBold(size: 13),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      prefixIcon: Icon(Icons.email_outlined, size: 18, color: AppTheme.ink900),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text('PASSWORD / PASSCODE', style: AppTheme.label(size: 9, color: AppTheme.muted)),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.paper,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppTheme.ink900, width: 1.2),
                                  ),
                                  child: TextField(
                                    controller: _adminPassCtrl,
                                    obscureText: _obscurePass,
                                    style: AppTheme.bodyBold(size: 13),
                                    decoration: InputDecoration(
                                      border: InputBorder.none,
                                      prefixIcon: const Icon(Icons.lock_outline, size: 18, color: AppTheme.ink900),
                                      suffixIcon: IconButton(
                                        icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility, size: 18, color: AppTheme.ink900),
                                        onPressed: () => setState(() => _obscurePass = !_obscurePass),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                NeoButton(
                                  backgroundColor: AppTheme.ink900,
                                  shadowColor: AppTheme.greenNeon,
                                  onTap: () => _loginAsAdmin(tele),
                                  child: Center(
                                    child: Text(
                                      'SIGN IN AS ADMIN / MANAGER →',
                                      style: AppTheme.label(size: 11, color: AppTheme.white, letterSpacing: 0.12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Tab 1: Caller Agent Login
                        if (_selectedTab == 1) ...[
                          NeoCard(
                            backgroundColor: AppTheme.white,
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'CALLER / AGENT ACCESS',
                                      style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.16),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.greenNeon,
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(color: AppTheme.ink900, width: 1),
                                      ),
                                      child: Text(
                                        'DEVICE SIM',
                                        style: AppTheme.label(size: 8, color: AppTheme.ink900),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  tele.verifiedTrackingNumber.isNotEmpty
                                      ? 'DEVICE PHONE: ${tele.verifiedTrackingNumber}'
                                      : 'ACTIVE SIM: ${tele.activeSimLabel}',
                                  style: AppTheme.headline(size: 18, color: AppTheme.ink900),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Automatic background call sync & lead capture enabled.',
                                  style: AppTheme.body(size: 12, color: AppTheme.muted),
                                ),
                                const SizedBox(height: 16),

                                // Auto Record Toggle Row
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.paper,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppTheme.ink900, width: 1.2),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.mic, color: AppTheme.greenDark, size: 22),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'ALWAYS AUTO-RECORD CALLS',
                                              style: AppTheme.label(size: 9, color: AppTheme.ink900, letterSpacing: 0.1),
                                            ),
                                            Text(
                                              'Automatically records audio during ongoing calls',
                                              style: AppTheme.body(size: 11, color: AppTheme.muted),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Switch(
                                        value: tele.autoRecordEnabled,
                                        activeThumbColor: AppTheme.greenNeon,
                                        activeTrackColor: AppTheme.ink900,
                                        onChanged: (_) => tele.toggleAutoRecord(),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                NeoButton.accent(
                                  onTap: () => _loginAsCaller(tele),
                                  child: Center(
                                    child: Text(
                                      'CONTINUE AS CALLER AGENT →',
                                      style: AppTheme.label(size: 11, color: AppTheme.ink900, letterSpacing: 0.12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
