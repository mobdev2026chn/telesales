import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../widgets/neo_button.dart';
import '../widgets/ticker_banner.dart';
import '../providers/tele_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _isLoading = false;
  UserRole _selectedRole = UserRole.manager;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _selectRole(UserRole role) {
    setState(() {
      _selectedRole = role;
    });
  }

  Future<void> _handleLogin(TeleProvider tele) async {
    final userText = _usernameCtrl.text.trim();
    final passText = _passwordCtrl.text.trim();

    if (userText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.ink900,
          content: Text('Please enter a username or email', style: AppTheme.bodyBold(size: 12, color: AppTheme.limeYellow)),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final success = await tele.performLogin(
      username: userText,
      password: passText,
      role: _selectedRole,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.ink900,
            content: Text('Authentication failed. Please check credentials.', style: AppTheme.bodyBold(size: 12, color: AppTheme.redMissed)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);

    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Top Dark Hero Header Card
                        Container(
                          margin: const EdgeInsets.all(12),
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                          decoration: BoxDecoration(
                            color: AppTheme.ink900,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Stack(
                            children: [
                              // Watermark '01'
                              Positioned(
                                right: 0,
                                top: -10,
                                child: Text(
                                  '01',
                                  style: AppTheme.headline(
                                    size: 96,
                                    color: AppTheme.white.withValues(alpha: 0.06),
                                  ),
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Official ASK EVA Logo Image & Badge
                                  Row(
                                    children: [
                                      Container(
                                        width: 54,
                                        height: 54,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: AppTheme.white, width: 1.5),
                                          boxShadow: AppTheme.neoShadowSm(color: AppTheme.greenNeon),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: Image.asset(
                                            'assets/images/ask_eva_logo.jpg',
                                            fit: BoxFit.cover,
                                            errorBuilder: (ctx, err, stack) => Container(
                                              color: AppTheme.greenNeon,
                                              child: Center(
                                                child: Text('ASK EVA', style: AppTheme.headline(size: 10, color: AppTheme.white)),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: AppTheme.greenNeon,
                                          borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(8),
                                            topRight: Radius.circular(8),
                                            bottomRight: Radius.circular(8),
                                            bottomLeft: Radius.circular(0),
                                          ),
                                          border: Border.all(color: AppTheme.ink900, width: 1.5),
                                        ),
                                        child: Text(
                                          'ASK EVA',
                                          style: AppTheme.headline(size: 16, color: AppTheme.white),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),

                                  // EVERY CALL IS A lead.
                                  RichText(
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text: 'EVERY CALL\nIS A ',
                                          style: AppTheme.headline(size: 40, color: AppTheme.white),
                                        ),
                                        TextSpan(
                                          text: 'lead',
                                          style: AppTheme.italicSerif(size: 40, color: AppTheme.greenGrass),
                                        ),
                                        TextSpan(
                                          text: '.',
                                          style: AppTheme.headline(size: 40, color: AppTheme.greenNeon),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Monitor telesales calls, track lead status and coach your callers from one dashboard.',
                                    style: AppTheme.body(size: 12, color: AppTheme.white.withValues(alpha: 0.7)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Ticker Banner Strip
                        const TickerBanner(),
                        const SizedBox(height: 16),

                        // Sign In Form Container
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Section Title
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(width: 8, height: 8, color: AppTheme.greenNeon),
                                      const SizedBox(width: 8),
                                      Text(
                                        'SELECT ROLE & SIGN IN',
                                        style: AppTheme.label(size: 11, color: AppTheme.ink900, letterSpacing: 0.18),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // ROLE SELECTOR TOGGLE BAR
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
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => _selectRole(UserRole.manager),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          decoration: BoxDecoration(
                                            color: _selectedRole == UserRole.manager ? AppTheme.ink900 : Colors.transparent,
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Center(
                                            child: Text(
                                              '👔 MANAGER',
                                              style: AppTheme.label(
                                                size: 10,
                                                color: _selectedRole == UserRole.manager ? AppTheme.limeYellow : AppTheme.ink900,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => _selectRole(UserRole.caller),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          decoration: BoxDecoration(
                                            color: _selectedRole == UserRole.caller ? AppTheme.ink900 : Colors.transparent,
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Center(
                                            child: Text(
                                              '📱 CALLER AGENT',
                                              style: AppTheme.label(
                                                size: 10,
                                                color: _selectedRole == UserRole.caller ? AppTheme.limeYellow : AppTheme.ink900,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Username Input
                              Text('USERNAME OR PHONE', style: AppTheme.label(size: 9, color: AppTheme.muted)),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppTheme.ink900, width: 1.5),
                                  boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                                ),
                                child: TextField(
                                  controller: _usernameCtrl,
                                  style: AppTheme.mono(size: 14, color: AppTheme.ink900),
                                  decoration: const InputDecoration(
                                    hintText: 'Enter username or phone number...',
                                    hintStyle: TextStyle(color: AppTheme.muted, fontSize: 12),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),

                              // Password Input
                              Text('PASSWORD', style: AppTheme.label(size: 9, color: AppTheme.muted)),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppTheme.ink900, width: 1.5),
                                  boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                                ),
                                child: TextField(
                                  controller: _passwordCtrl,
                                  obscureText: _obscurePass,
                                  style: AppTheme.mono(size: 14, color: AppTheme.ink900),
                                  decoration: InputDecoration(
                                    hintText: 'Enter password...',
                                    hintStyle: const TextStyle(color: AppTheme.muted, fontSize: 12),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePass ? Icons.remove_red_eye_outlined : Icons.visibility,
                                        size: 18,
                                        color: AppTheme.ink900,
                                      ),
                                      onPressed: () => setState(() => _obscurePass = !_obscurePass),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Sign In Button
                              NeoButton(
                                backgroundColor: AppTheme.ink900,
                                shadowColor: AppTheme.greenNeon,
                                onTap: () {
                                  if (!_isLoading) {
                                    _handleLogin(tele);
                                  }
                                },
                                child: Center(
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.limeYellow),
                                          ),
                                        )
                                      : Text(
                                          _selectedRole == UserRole.manager
                                              ? 'SIGN IN AS MANAGER →'
                                              : 'SIGN IN AS CALLER →',
                                          style: AppTheme.label(size: 11.5, color: AppTheme.limeYellow, letterSpacing: 0.14),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Forgot Password Link
                              Center(
                                child: TextButton(
                                  onPressed: () {},
                                  child: Text(
                                    'FORGOT PASSWORD?',
                                    style: AppTheme.label(
                                      size: 10,
                                      color: AppTheme.greenDark,
                                      letterSpacing: 0.12,
                                    ).copyWith(decoration: TextDecoration.underline),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
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
