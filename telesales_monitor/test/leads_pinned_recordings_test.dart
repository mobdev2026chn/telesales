import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telesales_monitor/models/recording_model.dart';
import 'package:telesales_monitor/providers/tele_provider.dart';
import 'package:telesales_monitor/screens/shared/leads_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.askeva.telesales/telephony'),
      (MethodCall methodCall) async => null,
    );
  });

  RecordingModel rec(String id, String client, {required bool pinned, required DateTime date}) => RecordingModel(
        id: id,
        agentName: 'Priya Caller',
        clientName: client,
        clientPhone: '98765432${id.padLeft(2, '0')}',
        date: date,
        duration: const Duration(minutes: 3, seconds: 5),
        note: '',
        pinned: pinned,
      );

  testWidgets('pinned recordings (old and new) are listed on the Leads page', (tester) async {
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final tele = TeleProvider();
    final now = DateTime.now();
    tele.debugSetRecordings([
      rec('1', 'Old Pinned Client', pinned: true, date: now.subtract(const Duration(days: 400))),
      rec('2', 'New Pinned Client', pinned: true, date: now.subtract(const Duration(hours: 2))),
      rec('3', 'Not Pinned Client', pinned: false, date: now),
      rec('4', 'Pinned Three', pinned: true, date: now.subtract(const Duration(days: 3))),
      rec('5', 'Pinned Four', pinned: true, date: now.subtract(const Duration(days: 30))),
    ]);
    await tester.pumpWidget(ChangeNotifierProvider<TeleProvider>.value(
      value: tele,
      child: const MaterialApp(home: LeadsScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('PINNED RECORDINGS · 4'), findsOneWidget);
    // Shown below the search box and the category filter
    final pinnedY = tester.getTopLeft(find.text('PINNED RECORDINGS · 4')).dy;
    expect(pinnedY, greaterThan(tester.getTopLeft(find.text('🏷️ ALL CATEGORIES')).dy));
    expect(pinnedY, greaterThan(tester.getTopLeft(find.text('Search lead or phone...')).dy));
    expect(find.text('Not Pinned Client'), findsNothing);
    // Newest first, three shown until VIEW ALL
    expect(find.text('New Pinned Client'), findsOneWidget);
    expect(find.text('Pinned Three'), findsOneWidget);
    expect(find.text('Pinned Four'), findsOneWidget);
    expect(find.text('Old Pinned Client'), findsNothing);
    await tester.tap(find.text('VIEW ALL 4 PINNED ↓'));
    await tester.pump();
    expect(find.text('Old Pinned Client'), findsOneWidget);
    expect(find.text('SHOW LESS ↑'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    tele.dispose();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('no pinned section when nothing is pinned', (tester) async {
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final tele = TeleProvider();
    tele.debugSetRecordings([rec('3', 'Not Pinned Client', pinned: false, date: DateTime.now())]);
    await tester.pumpWidget(ChangeNotifierProvider<TeleProvider>.value(
      value: tele,
      child: const MaterialApp(home: LeadsScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('PINNED RECORDINGS'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    tele.dispose();
    await tester.pump(const Duration(seconds: 1));
  });
}
