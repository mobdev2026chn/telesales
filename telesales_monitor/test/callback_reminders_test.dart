import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telesales_monitor/providers/tele_provider.dart';
import 'package:telesales_monitor/services/callback_reminders.dart';
import 'package:telesales_monitor/services/realtime_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.askeva.telesales/telephony');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(channel, (MethodCall c) async {
      calls.add(c);
      return c.method.contains('CallbackReminder') ? true : null;
    });
  });

  List<MethodCall> reminderCalls() => calls.where((c) => c.method.contains('CallbackReminder')).toList();

  test('reminder id, title and body', () {
    expect(CallbackReminders.reminderIdFor(phone: '+91 98250 12340', callbackId: '1'), '9825012340');
    expect(CallbackReminders.reminderIdFor(phone: '', callbackId: '17'), 'cb_17');
    expect(CallbackReminders.titleFor(name: 'Ravi', phone: '9825012340'), 'Callback due: Ravi');
    expect(CallbackReminders.titleFor(name: ' ', phone: '9825012340'), 'Callback due: 9825012340');
    expect(CallbackReminders.bodyFor(phone: '9825012340', note: 'Pricing'), '9825012340 · Pricing');
    expect(CallbackReminders.bodyFor(phone: '9825012340', note: ''), '9825012340');
  });

  testWidgets('a native build without the methods never throws', (tester) async {
    messenger.setMockMethodCallHandler(channel, null); // MissingPluginException
    CallbackReminders.schedule(
      id: '9825012340',
      at: DateTime.now().add(const Duration(hours: 1)),
      title: 't',
      body: 'b',
    );
    CallbackReminders.cancel('9825012340');
    CallbackReminders.cancelAll();
    await tester.pump();
  });

  testWidgets('callbacks are replaced by number, and only chosen future times get a reminder', (tester) async {
    final tele = TeleProvider();
    await tester.pump(const Duration(milliseconds: 50));
    calls.clear();
    final at = DateTime.now().add(const Duration(days: 1));

    tele.addScheduledCallback(name: 'Ravi', phone: '+91 98250 12340', scheduledTime: at, note: 'Pricing', remind: true);
    // Another lead with the same name keeps its own callback
    tele.addScheduledCallback(name: 'Ravi', phone: '9825012341', scheduledTime: at, note: 'x');
    await tester.pump();
    expect(tele.callbacks.length, 2);
    final scheduled = reminderCalls().where((c) => c.method == 'scheduleCallbackReminder').toList();
    expect(scheduled.length, 1); // the second one was not chosen by the agent (remind: false)
    expect(scheduled.single.arguments, {
      'id': '9825012340',
      'atMs': at.millisecondsSinceEpoch,
      'title': 'Callback due: Ravi',
      'body': '+91 98250 12340 · Pricing',
    });

    // Rescheduling the same number replaces it: old reminder cancelled, then the new one
    calls.clear();
    final later = at.add(const Duration(hours: 2));
    tele.addScheduledCallback(name: 'Ravi', phone: '9825012340', scheduledTime: later, note: '', remind: true);
    await tester.pump();
    expect(tele.callbacks.length, 2);
    expect(reminderCalls().map((c) => c.method), ['cancelCallbackReminder', 'scheduleCallbackReminder']);
    expect((reminderCalls().last.arguments as Map)['atMs'], later.millisecondsSinceEpoch);

    // A time in the past gets no reminder (the old one is still cancelled)
    calls.clear();
    tele.addScheduledCallback(
      name: 'Ravi',
      phone: '9825012340',
      scheduledTime: DateTime.now().subtract(const Duration(hours: 1)),
      note: '',
      remind: true,
    );
    await tester.pump();
    expect(reminderCalls().map((c) => c.method), ['cancelCallbackReminder']);

    tele.dispose();
    await tester.pump(const Duration(seconds: 1));
  });

  test('registering the same realtime handler again does not add it twice', () {
    void handler(dynamic _) {}
    void other(dynamic _) {}
    const event = 'testEventForDedupe';
    RealtimeService.on(event, handler);
    RealtimeService.on(event, handler); // e.g. a second login
    RealtimeService.disconnect();
    RealtimeService.on(event, handler); // and a third, after logout
    expect(RealtimeService.handlerCountFor(event), 1);
    RealtimeService.on(event, other); // a different handler is kept
    expect(RealtimeService.handlerCountFor(event), 2);
    RealtimeService.off(event);
    expect(RealtimeService.handlerCountFor(event), 0);
  });
}
