import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'providers/tele_provider.dart';
import 'screens/onboarding/callyzer_setup_flow.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppTheme.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const TelesalesApp());
}

class TelesalesApp extends StatelessWidget {
  const TelesalesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TeleProvider()),
      ],
      child: MaterialApp(
        title: 'ASKEVA Call Monitor',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: AppTheme.paper,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppTheme.greenNeon,
            primary: AppTheme.ink900,
            surface: AppTheme.paper,
          ),
          useMaterial3: true,
        ),
        home: Consumer<TeleProvider>(
          builder: (context, tele, _) {
            if (!tele.setupCompleted) {
              return const CallyzerSetupFlow();
            }
            return tele.isLoggedIn ? const MainShell() : const LoginScreen();
          },
        ),
      ),
    );
  }
}
