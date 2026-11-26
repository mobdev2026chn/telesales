// Phone reminders for follow-up callbacks the agent scheduled themselves. The native side
// (MethodChannel com.askeva.telesales/telephony) posts a notification at the time, opens the app on
// tap, and keeps the reminder across app close and reboot. Every call is fire-and-forget: a phone
// whose native build does not have these methods yet (MissingPluginException) just gets no reminder.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api_parsers.dart';

class CallbackReminders {
  CallbackReminders._();

  static const MethodChannel _channel = MethodChannel('com.askeva.telesales/telephony');

  /// Stable reminder id for a callback: one callback per number (last 10 digits), else its own id.
  static String reminderIdFor({required String phone, required String callbackId}) {
    final last10 = last10Digits(phone);
    return last10.isNotEmpty ? last10 : 'cb_$callbackId';
  }

  static String titleFor({required String name, required String phone}) {
    final who = name.trim().isNotEmpty ? name.trim() : phone.trim();
    return 'Callback due: $who';
  }

  static String bodyFor({required String phone, required String note}) {
    final n = note.trim();
    return n.isEmpty ? phone.trim() : '${phone.trim()} · $n';
  }

  /// Schedules a reminder at [at]. Past times are skipped. Never blocks, never throws.
  static void schedule({
    required String id,
    required DateTime at,
    required String title,
    required String body,
  }) {
    if (id.isEmpty || !at.isAfter(DateTime.now())) return;
    unawaited(_invoke('scheduleCallbackReminder', {
      'id': id,
      'atMs': at.millisecondsSinceEpoch,
      'title': title,
      'body': body,
    }));
  }

  /// Cancels the reminder [id] (no-op when there is none). Never blocks, never throws.
  static void cancel(String id) {
    if (id.isEmpty) return;
    unawaited(_invoke('cancelCallbackReminder', {'id': id}));
  }

  /// Cancels every callback reminder (logout). Never blocks, never throws.
  static void cancelAll() {
    unawaited(_invoke('cancelAllCallbackReminders'));
  }

  static Future<bool> _invoke(String method, [Map<String, dynamic>? args]) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } on MissingPluginException {
      return false; // native build without callback reminders
    } on PlatformException catch (e) {
      debugPrint('CallbackReminders.$method failed: ${e.code} ${e.message ?? ''}');
      return false;
    } catch (e) {
      debugPrint('CallbackReminders.$method failed: $e');
      return false;
    }
  }
}
