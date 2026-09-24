import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telesales_monitor/models/call_log_model.dart';
import 'package:telesales_monitor/providers/tele_provider.dart';
import 'package:telesales_monitor/widgets/post_call_demo_prompt.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.askeva.telesales/telephony'),
      (MethodCall methodCall) async => null,
    );
  });

  Future<TeleProvider> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final key = GlobalKey<NavigatorState>();
    final tele = TeleProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<TeleProvider>.value(
        value: tele,
        child: MaterialApp(
          navigatorKey: key,
          home: const Scaffold(body: Text('HOME')),
          builder: (context, child) => PostCallDemoPrompt(navigatorKey: key, child: child!),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return tele;
  }

  Future<void> closeApp(WidgetTester tester, TeleProvider tele) async {
    await tester.pumpWidget(const SizedBox());
    tele.dispose();
    await tester.pump(const Duration(seconds: 1));
  }

  CallLogModel call() => CallLogModel(
        id: 'k1',
        contactName: 'Ravi Traders',
        phoneNumber: '9876543210',
        type: CallType.outgoing,
        duration: const Duration(seconds: 95),
        timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
      );

  testWidgets('a finished call shows the demo pop-up and BOOK DEMO opens the form', (tester) async {
    final tele = await pumpApp(tester);
    tele.debugShowDemoPrompt(call());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('BOOK A DEMO?'), findsOneWidget);
    expect(find.text('Ravi Traders'), findsOneWidget);
    expect(find.text('9876543210'), findsOneWidget);
    expect(find.textContaining('CALL ENDED · OUTGOING'), findsOneWidget);

    await tester.tap(find.text('BOOK DEMO →'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Step 1: hourly slots
    expect(find.text('BOOK A DEMO?'), findsNothing);
    expect(find.text('BOOK DEMO SLOT'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\d{1,2}:00 (AM|PM) - \d{1,2}:00 (AM|PM)$')), findsNWidgets(9));
    expect(find.text('+ BOOK'), findsWidgets);
    expect(tele.pendingDemoPromptCall, isNull);

    // Step 2: the BOOK DEMO SLOT form, client prefilled from the call
    await tester.tap(find.text('+ BOOK').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    for (final label in ['CALLER', 'CLIENT NAME', 'CLIENT PHONE', 'CLASS / COURSE', 'NOTES (OPTIONAL)', 'CLOSE', 'BOOK SLOT']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.widgetWithText(TextField, 'Ravi Traders'), findsOneWidget);
    expect(find.widgetWithText(TextField, '9876543210'), findsOneWidget);

    // Class / course is required
    await tester.tap(find.text('BOOK SLOT'));
    await tester.pump();
    expect(find.text('Enter the class / course.'), findsOneWidget);

    // CLOSE goes back to the slot list
    await tester.tap(find.text('CLOSE'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('CLIENT NAME'), findsNothing);
    expect(find.text('+ BOOK'), findsWidgets);
    await closeApp(tester, tele);
  });

  testWidgets('a demo booked from the pop-up is remembered for the outcome screen', (tester) async {
    final tele = await pumpApp(tester);
    final demoAt = DateTime.now().add(const Duration(days: 1));
    final lead = tele.leadForCall(call());
    expect(lead.name, 'Ravi Traders');
    expect(tele.recentDemoBookingFor('+91 98765 43210'), isNull);
    await tele.markDemoBooked(lead, demoAt, 'Ravi Traders Pvt Ltd');
    expect(tele.recentDemoBookingFor('+91 98765 43210'), demoAt);
    expect(tele.recentDemoBookingFor('9000000000'), isNull);
    await closeApp(tester, tele);
  });

  testWidgets('NOT NOW closes the pop-up without opening the form', (tester) async {
    final tele = await pumpApp(tester);
    tele.debugShowDemoPrompt(call());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('NOT NOW'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('BOOK A DEMO?'), findsNothing);
    expect(find.text('BOOK APPOINTMENT →'), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
    await closeApp(tester, tele);
  });
}
