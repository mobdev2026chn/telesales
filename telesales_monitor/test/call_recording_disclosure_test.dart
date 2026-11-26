import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telesales_monitor/widgets/call_recording_disclosure.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  /// Opens the disclosure from a button and records what [askCallRecordingConsent] returned.
  Future<List<bool>> pumpAsker(WidgetTester tester) async {
    final results = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => results.add(await askCallRecordingConsent(context)),
          child: const Text('turn on'),
        ),
      ),
    ));
    return results;
  }

  testWidgets('explains the service and the data, then AGREE is remembered', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final results = await pumpAsker(tester);

    await tester.tap(find.text('turn on'));
    await tester.pumpAndSettle();
    expect(find.text('DATA COLLECTED'), findsOneWidget);
    expect(find.textContaining('Accessibility service'), findsOneWidget);

    await tester.tap(find.text('AGREE'));
    await tester.pumpAndSettle();
    expect(results, [true]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kCallRecordingDisclosureKey), isTrue);

    // Asked once: the next time it is not shown again
    await tester.tap(find.text('turn on'));
    await tester.pumpAndSettle();
    expect(find.text('DATA COLLECTED'), findsNothing);
    expect(results, [true, true]);
  });

  testWidgets('NO THANKS keeps recording off and asks again next time', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final results = await pumpAsker(tester);

    await tester.tap(find.text('turn on'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NO THANKS'));
    await tester.pumpAndSettle();
    expect(results, [false]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kCallRecordingDisclosureKey), isNull);

    await tester.tap(find.text('turn on'));
    await tester.pumpAndSettle();
    expect(find.text('DATA COLLECTED'), findsOneWidget);
  });
}
