import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../widgets/neo_button.dart';
import '../widgets/ticker_banner.dart';
import '../providers/tele_provider.dart';
import '../services/api_service.dart';
import 'main_shell.dart';

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
  UserRole _selectedRole = UserRole.caller;
  String? _usernameError;
  String? _passwordError;
  String? _authError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tele = Provider.of<TeleProvider>(context, listen: false);
      if (tele.verifiedTrackingNumber.isNotEmpty) {
        final cleanPhone = tele.verifiedTrackingNumber.replaceAll('+91', '').trim();
        setState(() {
          _usernameCtrl.text = cleanPhone;
          _selectedRole = UserRole.caller;
        });
      }
    });
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _selectRole(UserRole role) {
    setState(() {
      _selectedRole = role;
      _usernameError = null;
      _passwordError = null;
      _authError = null;
      _usernameCtrl.clear();
      _passwordCtrl.clear();
    });
  }

  Future<void> _handleLogin(TeleProvider tele) async {
    final userText = _usernameCtrl.text.trim();
    final passText = _passwordCtrl.text.trim();

    setState(() {
      _usernameError = null;
      _passwordError = null;
      _authError = null;
    });

    bool isValid = true;

    if (userText.isEmpty) {
      setState(() => _usernameError = 'Please enter an email or username');
      isValid = false;
    } else if (userText.contains('@') && !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(userText)) {
      setState(() => _usernameError = 'Please enter a valid email address');
      isValid = false;
    }

    if (passText.isEmpty) {
      setState(() => _passwordError = 'Please enter your password');
      isValid = false;
    } else if (passText.length < 3) {
      setState(() => _passwordError = 'Password must be at least 3 characters');
      isValid = false;
    }

    if (!isValid) return;

    setState(() => _isLoading = true);

    final result = await tele.performLogin(
      username: userText,
      password: passText,
      role: _selectedRole,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (result['requiresPhoneInput'] == true) {
        _showMobileNumberVerificationSheet(context, tele, result['user'] as Map<String, dynamic>?);
      } else if (result['success'] == true) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const MainShell(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
      } else {
        final errMsg = result['message'] as String? ?? 'Invalid credentials. User not found in database or incorrect password.';
        setState(() => _authError = errMsg);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.ink900,
            content: Text(errMsg, style: AppTheme.bodyBold(size: 12, color: AppTheme.redMissed)),
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
                                        width: 58,
                                        height: 58,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: AppTheme.white, width: 1.5),
                                          boxShadow: AppTheme.neoShadowSm(color: AppTheme.greenNeon),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Image.asset(
                                            'assets/images/ask_eva_logo.png',
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
                              if (_authError != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppTheme.redMissed, width: 1.5),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error_outline, color: AppTheme.redMissed, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _authError!,
                                          style: AppTheme.bodyBold(size: 11, color: AppTheme.redMissed),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),

                              // Username Input
                              Text('USERNAME OR PHONE', style: AppTheme.label(size: 9, color: AppTheme.muted)),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: _usernameError != null ? AppTheme.redMissed : AppTheme.ink900, width: 1.5),
                                  boxShadow: AppTheme.neoShadowSm(color: _usernameError != null ? AppTheme.redMissed : AppTheme.ink900),
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
                              if (_usernameError != null) ...[
                                const SizedBox(height: 4),
                                Text(_usernameError!, style: AppTheme.label(size: 9.5, color: AppTheme.redMissed)),
                              ],
                              const SizedBox(height: 14),

                              // Password Input
                              Text('PASSWORD', style: AppTheme.label(size: 9, color: AppTheme.muted)),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: _passwordError != null ? AppTheme.redMissed : AppTheme.ink900, width: 1.5),
                                  boxShadow: AppTheme.neoShadowSm(color: _passwordError != null ? AppTheme.redMissed : AppTheme.ink900),
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
                              if (_passwordError != null) ...[
                                const SizedBox(height: 4),
                                Text(_passwordError!, style: AppTheme.label(size: 9.5, color: AppTheme.redMissed)),
                              ],
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

  void _showMobileNumberVerificationSheet(BuildContext context, TeleProvider tele, Map<String, dynamic>? user) {
    final phoneCtrl = TextEditingController();
    String? sheetErr;
    bool isVerifying = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: const BoxDecoration(
                color: AppTheme.paper,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.muted,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.sim_card_outlined, color: AppTheme.greenDark, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'VERIFY DEVICE SIM NUMBER',
                        style: AppTheme.headline(size: 16, color: AppTheme.ink900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You logged in as ${user?['email'] ?? 'Caller'}. Please enter your 10-digit mobile SIM number inserted in this phone to complete hardware verification:',
                    style: AppTheme.body(size: 12, color: AppTheme.ink700),
                  ),
                  const SizedBox(height: 16),

                  if (sheetErr != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.redMissed, width: 1),
                      ),
                      child: Text(
                        sheetErr!,
                        style: AppTheme.bodyBold(size: 11, color: AppTheme.redMissed),
                      ),
                    ),
                  ],

                  Text('SIM MOBILE NUMBER', style: AppTheme.label(size: 9, color: AppTheme.muted)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.ink900, width: 1.5),
                    ),
                    child: TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      style: AppTheme.mono(size: 14, color: AppTheme.ink900),
                      decoration: const InputDecoration(
                        hintText: 'Enter 10-digit SIM number (e.g. 9842399615)...',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  NeoButton.accent(
                    gradient: null,
                    backgroundColor: AppTheme.greenNeon,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    onTap: isVerifying
                        ? () {}
                        : () async {
                            final raw = phoneCtrl.text.trim();
                            if (raw.isEmpty) {
                              setSheetState(() => sheetErr = 'Please enter your mobile SIM number.');
                              return;
                            }
                            setSheetState(() {
                              isVerifying = true;
                              sheetErr = null;
                            });
                            final res = await ApiService.linkPhone(
                              userId: user?['id']?.toString() ?? '',
                              email: user?['email']?.toString() ?? '',
                              phone: raw,
                            );
                            if (res != null && res['success'] == true) {
                              if (ctx.mounted) {
                                Navigator.of(ctx).pop();
                                _handleLogin(tele);
                              }
                            } else {
                              setSheetState(() {
                                isVerifying = false;
                                sheetErr = res?['message']?.toString() ?? 'SIM verification failed.';
                              });
                            }
                          },
                    child: Center(
                      child: isVerifying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(color: AppTheme.ink900, strokeWidth: 2),
                            )
                          : Text('VERIFY & LINK SIM', style: AppTheme.headline(size: 14, color: AppTheme.ink900)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
