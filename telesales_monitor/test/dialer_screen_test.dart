import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:telesales_monitor/providers/tele_provider.dart';
import 'package:telesales_monitor/screens/caller/dialer_screen.dart';

void main() {
  testWidgets('DialerScreen renders keypad, displays typed numbers and handles backspace', (tester) async {
    final tele = TeleProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TeleProvider>.value(value: tele),
        ],
        child: const MaterialApp(
          home: DialerScreen(),
        ),
      ),
    );

    // Initial check: placeholder is visible
    expect(find.text('Enter number…'), findsOneWidget);
    expect(find.text('CUSTOM KEYPAD'), findsOneWidget);

    // Verify key 1, 2, 3, etc. are rendered
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('*'), findsOneWidget);
    expect(find.text('#'), findsOneWidget);

    // Tap digits '9', '8', '7'
    await tester.tap(find.text('9'));
    await tester.pump();
    await tester.tap(find.text('8'));
    await tester.pump();
    await tester.tap(find.text('7'));
    await tester.pump();

    // Verify entered number shows 987
    expect(find.text('987'), findsOneWidget);

    // Tap backspace icon
    final backspace = find.byIcon(Icons.backspace_outlined);
    expect(backspace, findsOneWidget);
    await tester.tap(backspace);
    await tester.pump();

    // Number should now be 98
    expect(find.text('98'), findsOneWidget);

    // Tap CLEAR button
    final clearBtn = find.text('CLEAR');
    expect(clearBtn, findsOneWidget);
    await tester.tap(clearBtn);
    await tester.pump();

    // Should return to placeholder
    expect(find.text('Enter number…'), findsOneWidget);
  });
}
