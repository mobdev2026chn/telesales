import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telesales_monitor/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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

  Future<void> pumpPastSplash(WidgetTester tester) async {
    await tester.pumpWidget(const TelesalesApp());
    // Splash: waits for saved state, then ~1.4 s animation, then a 400 ms fade
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('Fresh install opens the onboarding flow', (WidgetTester tester) async {
    await pumpPastSplash(tester);
    expect(find.text('Your privacy is important to us'), findsOneWidget);
    expect(find.text('AGREE & CONTINUE'), findsOneWidget);
  });

  testWidgets('A saved session without a real token must sign in again', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'setup_completed': true,
      'is_logged_in': true,
      'auth_token': 'jwt_caller_token_1_123', // fake token written by old builds
      'caller_name': 'Old User',
      'current_user_id': '1',
      'lead_notes_json': '{"9825012340":"secret note"}',
    });
    await pumpPastSplash(tester);
    expect(find.text('SELECT ROLE & SIGN IN'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('is_logged_in'), isFalse);
    expect(prefs.getString('auth_token'), isNull);
    expect(prefs.getString('caller_name'), isNull);
    expect(prefs.getString('lead_notes_json'), isNull);
  });
}
