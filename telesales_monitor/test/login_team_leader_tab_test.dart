import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telesales_monitor/providers/tele_provider.dart';
import 'package:telesales_monitor/screens/login_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.askeva.telesales/telephony'),
      (MethodCall methodCall) async => null,
    );
  });

  // 360 dp wide: a small phone, so the three tab labels must still fit
  testWidgets('login screen has Manager, Team Leader and Caller tabs', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final tele = TeleProvider();
    await tester.pumpWidget(ChangeNotifierProvider<TeleProvider>.value(
      value: tele,
      child: const MaterialApp(home: LoginScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('👔 MANAGER'), findsOneWidget);
    expect(find.text('🧭 TEAM LEADER'), findsOneWidget);
    expect(find.text('📱 CALLER'), findsOneWidget);
    expect(find.text('SIGN IN AS CALLER →'), findsOneWidget);

    await tester.tap(find.text('🧭 TEAM LEADER'));
    await tester.pump();
    expect(find.text('SIGN IN AS TEAM LEADER →'), findsOneWidget);

    await tester.tap(find.text('👔 MANAGER'));
    await tester.pump();
    expect(find.text('SIGN IN AS MANAGER →'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    tele.dispose();
    await tester.pump(const Duration(seconds: 1));
  });
}
