import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telesales_monitor/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.askeva.telesales/telephony'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getSimCards') {
          return [
            {
              'slotIndex': 0,
              'subscriptionId': 1,
              'displayName': 'Jio True5G',
              'carrierName': 'Jio',
              'number': '9825012340',
              'countryIso': 'in',
            }
          ];
        }
        if (methodCall.method == 'requestPermissions') {
          return true;
        }
        if (methodCall.method == 'validateSimNumber') {
          return {
            'isValid': true,
            'isHardwareMatch': true,
            'slotIndex': 0,
            'carrierName': 'Jio True5G',
            'formattedNumber': '+91 98250 12340',
          };
        }
        if (methodCall.method == 'getCallLogs') {
          return [
            {
              'id': '101',
              'contactName': 'ALAN 🤍',
              'phoneNumber': '+919342461344',
              'type': 'outgoing',
              'duration': 0,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'simSlot': 1,
            },
            {
              'id': '102',
              'contactName': 'Unknown',
              'phoneNumber': '+918778562066',
              'type': 'missed',
              'duration': 0,
              'timestamp': DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
              'simSlot': 1,
            },
          ];
        }
        if (methodCall.method == 'directCall') {
          return true;
        }
        return null;
      },
    );
  });

  testWidgets('Full Callyzer multi-step onboarding and SIM verification smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TelesalesApp());
    await tester.pump(const Duration(milliseconds: 100));

    // Step 0: Privacy Policy
    expect(find.text('Your privacy is important to us'), findsOneWidget);
    final agreeBtn = find.text('AGREE & CONTINUE');
    await tester.ensureVisible(agreeBtn);
    await tester.tap(agreeBtn);
    await tester.pump(const Duration(milliseconds: 300));

    // Step 1: Access to Call Log
    expect(find.text('ACCESS TO YOUR DEVICE\'S CALL LOG'), findsOneWidget);
    final allowBtn = find.text('Allow Access');
    await tester.ensureVisible(allowBtn);
    await tester.tap(allowBtn);
    await tester.pump(const Duration(milliseconds: 300));

    // Step 2: Set Default Phone App
    expect(find.text('Set Default Phone App'), findsOneWidget);
    final defaultBtn = find.text('Set as default');
    await tester.ensureVisible(defaultBtn);
    await tester.tap(defaultBtn);
    await tester.pump(const Duration(milliseconds: 300));

    // Step 3: Contacts Access
    expect(find.text('Contacts Access'), findsOneWidget);
    final letsDoItBtn = find.text('Let\'s do it');
    await tester.ensureVisible(letsDoItBtn);
    await tester.tap(letsDoItBtn);
    await tester.pump(const Duration(milliseconds: 300));

    // Step 4: Connect SIM
    expect(find.text('Connect Sim'), findsOneWidget);
    final submitBtn = find.text('SUBMIT');
    await tester.ensureVisible(submitBtn);
    await tester.tap(submitBtn);
    await tester.pump(const Duration(milliseconds: 300));

    // Step 5: SIM Verification Option
    expect(find.text('Choose one of the option to verify your number'), findsOneWidget);
    final skipBtn = find.text('Skip Verification');
    await tester.ensureVisible(skipBtn);
    await tester.tap(skipBtn);
    await tester.pump(const Duration(milliseconds: 300));

    // What's New Dialog & Got it
    expect(find.text('What\'s New'), findsOneWidget);
    final gotItBtn = find.text('Got it !');
    await tester.ensureVisible(gotItBtn);
    await tester.tap(gotItBtn);
    await tester.pumpAndSettle();

    // Arrive directly at Main App Shell (default CALLS tab active)
    expect(find.text('CALL HISTORY'), findsOneWidget);
    expect(find.text('ALAN 🤍'), findsOneWidget);
  });
}
