import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/tele_provider.dart';
import 'onboarding/callyzer_setup_flow.dart';
import 'login_screen.dart';
import 'main_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scaleAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack),
    );

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn),
    );

    _animCtrl.forward();

    _navigateNext();
  }

  Future<void> _navigateNext() async {
    final tele = Provider.of<TeleProvider>(context, listen: false);
    // Wait for saved preferences (login state, setupCompleted) to load from device disk
    await tele.initializationDone;
    // Ensure the splash animation finishes smoothly
    await Future.delayed(const Duration(milliseconds: 1400));

    if (!mounted) return;

    Widget nextScreen;
    if (tele.setupCompleted) {
      if (tele.isLoggedIn) {
        nextScreen = const MainShell();
      } else {
        nextScreen = const LoginScreen();
      }
    } else {
      nextScreen = const CallyzerSetupFlow();
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => nextScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.ink900,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Ask EVA Logo Card
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: AppTheme.ink800,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.limeYellow, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.greenNeon.withValues(alpha: 0.35),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                      const BoxShadow(
                        color: AppTheme.ink900,
                        offset: Offset(4, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset(
                      'assets/images/ask_eva_logo.png',
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stack) => Container(
                        color: AppTheme.greenNeon,
                        child: Center(
                          child: Text('ASK EVA', style: AppTheme.headline(size: 16, color: AppTheme.white)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // App Title & Tagline
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('ASK EVA', style: AppTheme.headline(size: 24, color: AppTheme.white)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.greenNeon,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('CRM', style: AppTheme.label(size: 10, color: AppTheme.ink900)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'TELECALLING & CALL MONITORING',
                  style: AppTheme.label(size: 9.5, color: AppTheme.lightMuted, letterSpacing: 0.16),
                ),
                const SizedBox(height: 36),

                // Sleek Neon Progress Bar
                SizedBox(
                  width: 140,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: const LinearProgressIndicator(
                      backgroundColor: AppTheme.ink800,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.greenNeon),
                      minHeight: 4,
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
