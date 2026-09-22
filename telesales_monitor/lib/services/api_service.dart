import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/call_log_model.dart';
import '../models/employee_model.dart';
import '../models/lead_model.dart';
import '../models/recording_model.dart';
import 'api_parsers.dart';

/// All HTTP traffic goes through [ApiService._request], which attaches the session's
/// `Authorization: Bearer <JWT>` header and reports expired sessions (401 AUTH_REQUIRED).
class ApiService {
  static const String productionBaseUrl = 'https://telesales.askeva.io/api';

  /// Override per build: `flutter build apk --dart-define=API_URL=https://staging.example.com/api`.
  static const String configuredBaseUrl = String.fromEnvironment('API_URL', defaultValue: productionBaseUrl);

  /// Local backend on the Android emulator host. Only ever tried in debug builds.
  static const String debugEmulatorBaseUrl = 'http://10.0.2.2:5004/api';

  static List<String> get candidateBaseUrls => [
        configuredBaseUrl,
        if (kDebugMode && configuredBaseUrl != debugEmulatorBaseUrl) debugEmulatorBaseUrl,
      ];

  static String baseUrl = configuredBaseUrl;

  static String _token = '';
  static String get token => _token;
  static void setToken(String token) => _token = token;
  static void clearToken() => _token = '';

  /// Called when the server says the session is gone (HTTP 401 with code AUTH_REQUIRED).
  static void Function()? onAuthRequired;

  static final http.Client _client = http.Client();

  static const Set<String> _publicAuthPaths = {
    '/auth/login',
    '/auth/admin-login',
    '/auth/caller-verify',
    '/auth/check-phone',
  };

  /// Why the last request that returned null failed, in words a caller can act on ("" = no failure).
  static String lastNetworkError = '';

  /// Plain-language reason for a network failure.
  @visibleForTesting
  static String describeNetworkError(Object e) {
    final raw = e.toString();
    final msg = raw.toLowerCase();
    if (e is TimeoutException) return 'The server took too long to answer (slow or unstable internet).';
    if (e is HandshakeException || msg.contains('certificate') || msg.contains('handshake')) {
      return 'Secure connection failed. Check that the phone\'s date & time are set to automatic.';
    }
    if (msg.contains('failed host lookup') || msg.contains('no address associated')) {
      return 'This phone cannot find the server (no internet, or Private DNS / VPN / network permission blocking the app).';
    }
    if (msg.contains('network is unreachable') || msg.contains('no route to host')) {
      return 'No internet connection on this phone.';
    }
    if (msg.contains('connection refused') || msg.contains('connection reset')) {
      return 'The server refused the connection. Try again in a minute.';
    }
    return raw.length > 160 ? raw.substring(0, 160) : raw;
  }

  /// True for failures where the request certainly never reached the server
  /// (DNS failure, connection refused, TLS handshake). Only these may be retried on another host.
  @visibleForTesting
  static bool isConnectionError(Object e) {
    if (e is HandshakeException) return true;
    String msg;
    if (e is SocketException) {
      msg = '${e.message} ${e.osError?.message ?? ''}';
    } else if (e is http.ClientException) {
      msg = e.message;
    } else {
      return false;
    }
    msg = msg.toLowerCase();
    return msg.contains('failed host lookup') ||
        msg.contains('connection refused') ||
        msg.contains('network is unreachable') ||
        msg.contains('no route to host') ||
        msg.contains('no address associated') ||
        msg.contains('connection failed');
  }

  /// Central request helper. Returns null when no server could be reached (or the request timed out).
  static Future<http.Response?> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final tokenAtSend = _token;
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (tokenAtSend.isNotEmpty) 'Authorization': 'Bearer $tokenAtSend',
    };
    final hosts = [baseUrl, ...candidateBaseUrls.where((u) => u != baseUrl)];
    String? firstError; // the main host's failure is the one worth showing
    for (final base in hosts) {
      final uri = Uri.parse('$base$path');
      try {
        final http.Response res;
        switch (method) {
          case 'GET':
            res = await _client.get(uri, headers: headers).timeout(timeout);
            break;
          case 'DELETE':
            res = await _client.delete(uri, headers: headers).timeout(timeout);
            break;
          case 'PUT':
            res = await _client.put(uri, headers: headers, body: jsonEncode(body ?? const {})).timeout(timeout);
            break;
          default:
            res = await _client.post(uri, headers: headers, body: jsonEncode(body ?? const {})).timeout(timeout);
        }
        baseUrl = base;
        lastNetworkError = '';
        _checkAuthExpired(res, path, tokenAtSend);
        return res;
      } catch (e) {
        firstError ??= describeNetworkError(e);
        if (isConnectionError(e)) {
          debugPrint('ApiService: $base unreachable ($e), trying next host');
          continue;
        }
        // Timeout or failure after the request may have been sent: never replay it on another host.
        debugPrint('ApiService.$method $path failed: $e');
        lastNetworkError = firstError;
        return null;
      }
    }
    lastNetworkError = firstError ?? '';
    return null;
  }

  static void _checkAuthExpired(http.Response res, String path, String tokenAtSend) {
    if (res.statusCode != 401) return;
    final cleanPath = path.split('?').first;
    if (_publicAuthPaths.contains(cleanPath)) return;
    if (tokenAtSend != _token) return; // a newer session already replaced this one
    try {
      final data = jsonDecode(res.body);
      if (data is Map && data['code'] == 'AUTH_REQUIRED') {
        onAuthRequired?.call();
      }
    } catch (_) {}
  }

  static Map<String, dynamic>? _decodeMap(http.Response? res) {
    if (res == null) return null;
    try {
      final d = jsonDecode(res.body);
      return d is Map<String, dynamic> ? d : null;
    } catch (_) {
      return null;
    }
  }

  static bool _ok(http.Response? res) => res != null && res.statusCode >= 200 && res.statusCode < 300;

  static String _query(Map<String, String?> params) {
    final parts = <String>[];
    params.forEach((k, v) {
      if (v != null && v.isNotEmpty) parts.add('$k=${Uri.encodeComponent(v)}');
    });
    return parts.isEmpty ? '' : '?${parts.join('&')}';
  }

  // ------------------------------------------------------------------ Auth

  /// POST /auth/admin-login (manager tab) or /auth/caller-verify (caller tab).
  /// Returns the decoded server response, or null when the server could not be reached.
  static Future<Map<String, dynamic>?> login({
    required String identifier,
    required String password,
    required bool asManager,
    int? simSlot,
  }) async {
    final res = await _request('POST', asManager ? '/auth/admin-login' : '/auth/caller-verify', body: {
      'identifier': identifier.trim(),
      'password': password,
      if (!asManager && simSlot != null) 'simSlot': simSlot,
    });
    if (res == null) return null;
    final data = _decodeMap(res);
    if (data == null) {
      return {'success': false, 'message': 'Unexpected server response (HTTP ${res.statusCode}).'};
    }
    if (!_ok(res)) data['success'] = false;
    return data;
  }

  /// GET /auth/me. Returns `{success, user}`; null when offline.
  /// POST /auth/logout: the admin dashboard shows this user as offline straight away. Best effort.
  static Future<void> logout() async {
    if (_token.isEmpty) return;
    await _request('POST', '/auth/logout', timeout: const Duration(seconds: 5));
  }

  static Future<Map<String, dynamic>?> fetchMe() async {
    final res = await _request('GET', '/auth/me');
    if (res == null) return null;
    final data = _decodeMap(res) ?? {};
    if (!_ok(res)) data['success'] = false;
    data['statusCode'] = res.statusCode;
    return data;
  }

  /// POST /auth/link-phone (Bearer) — links the signed-in user's own number.
  static Future<Map<String, dynamic>?> linkPhone({required String phone}) async {
    final res = await _request('POST', '/auth/link-phone', body: {'phone': phone});
    if (res == null) return null;
    final data = _decodeMap(res) ?? {};
    if (!_ok(res)) data['success'] = false;
    return data;
  }

  /// POST /auth/check-phone (public). Response user is `{name, phone, role}` only.
  static Future<Map<String, dynamic>?> checkPhoneRegistered(String phoneNumber) async {
    final last10 = last10Digits(phoneNumber);
    final res = await _request('POST', '/auth/check-phone', body: {'phoneNumber': last10});
    if (res == null) return null;
    final data = _decodeMap(res) ?? {};
    if (!_ok(res)) {
      data['success'] = false;
      data['message'] ??= "Mobile number '$last10' is not registered. Please contact your manager or admin to add your account.";
    }
    return data;
  }

  // ------------------------------------------------------------------ Calls

  /// Sync calls to the backend. Returns the number of newly stored calls, or -1 on failure.
  static Future<int> syncCallLogs(
    List<CallLogModel> calls, {
    required String callerId,
    String callerName = '',
    String callerPhone = '',
  }) async {
    final payload = {
      'callerId': callerId,
      'callerName': callerName,
      'callerPhone': callerPhone,
      'calls': calls
          .map((c) => {
                'contactName': c.contactName,
                'phoneNumber': c.phoneNumber,
                'type': c.type.name,
                // UTC with 'Z' so the server stores the exact instant whatever its own timezone is
                'timestamp': c.timestamp.toUtc().toIso8601String(),
                'durationSeconds': c.duration.inSeconds,
                'simSlot': c.simSlot,
                'note': c.note ?? '',
              })
          .toList(),
    };
    // Server de-duplicates (caller + number + exact time), so a later retry of the same batch is harmless.
    final res = await _request('POST', '/calls/sync', body: payload, timeout: const Duration(seconds: 30));
    if (!_ok(res)) return -1;
    final data = _decodeMap(res) ?? {};
    return asInt(data['count'] ?? data['syncedCount']);
  }

  // ------------------------------------------------------------------ Dashboard / leaderboard

  static Map<String, String?> _scopeQuery({
    String? callerPhone,
    String? callerName,
    String? team,
    String? userId,
    String? timeFilter,
    String? period,
    String? date,
    String? startDate,
    String? endDate,
    String? loggedInRole,
    String? loggedInTeam,
    String? loggedInUserId,
  }) =>
      {
        'callerPhone': callerPhone,
        'callerName': callerName,
        'team': team,
        'userId': userId,
        'timeFilter': timeFilter,
        'period': period,
        'date': date,
        'startDate': startDate,
        'endDate': endDate,
        'loggedInRole': loggedInRole,
        'loggedInTeam': loggedInTeam,
        'loggedInUserId': loggedInUserId,
      };

  static Future<Map<String, dynamic>?> fetchDashboardStats({
    String? callerPhone,
    String? callerName,
    String? team,
    String? userId,
    String? timeFilter,
    String? period,
    String? date,
    String? startDate,
    String? endDate,
    String? loggedInRole,
    String? loggedInTeam,
    String? loggedInUserId,
  }) async {
    final q = _query(_scopeQuery(
      callerPhone: callerPhone,
      callerName: callerName,
      team: team,
      userId: userId,
      timeFilter: timeFilter,
      period: period,
      date: date,
      startDate: startDate,
      endDate: endDate,
      loggedInRole: loggedInRole,
      loggedInTeam: loggedInTeam,
      loggedInUserId: loggedInUserId,
    ));
    final res = await _request('GET', '/dashboard/stats$q');
    if (!_ok(res)) return null;
    final data = _decodeMap(res);
    final stats = data?['stats'] ?? data?['data'];
    return stats is Map<String, dynamic> ? stats : null;
  }

  static Future<List<EmployeeModel>?> fetchLeaderboard({
    String? callerPhone,
    String? callerName,
    String? team,
    String? userId,
    String? timeFilter,
    String? period,
    String? date,
    String? startDate,
    String? endDate,
    String? loggedInRole,
    String? loggedInTeam,
    String? loggedInUserId,
  }) async {
    final q = _query(_scopeQuery(
      callerPhone: callerPhone,
      callerName: callerName,
      team: team,
      userId: userId,
      timeFilter: timeFilter,
      period: period,
      date: date,
      startDate: startDate,
      endDate: endDate,
      loggedInRole: loggedInRole,
      loggedInTeam: loggedInTeam,
      loggedInUserId: loggedInUserId,
    ));
    final res = await _request('GET', '/employees/leaderboard$q');
    if (!_ok(res)) return null;
    final data = _decodeMap(res);
    final list = data?['employees'] ?? data?['data'];
    if (list is! List) return null;
    return list.whereType<Map>().map((e) => employeeFromJson(Map<String, dynamic>.from(e))).toList();
  }

  static Future<bool> uploadProfilePhoto({required String userId, required String photoBase64}) async {
    final res = await _request('POST', '/users/photo', body: {'photoBase64': photoBase64});
    return _ok(res);
  }

  // ------------------------------------------------------------------ Leads

  static Future<List<LeadModel>?> fetchLeads({
    String? callerPhone,
    String? callerName,
    String? team,
    String? userId,
    String? loggedInRole,
    String? loggedInTeam,
    String? loggedInUserId,
  }) async {
    final q = _query({
      ..._scopeQuery(
        callerPhone: callerPhone,
        callerName: callerName,
        team: team,
        userId: userId,
        loggedInRole: loggedInRole,
        loggedInTeam: loggedInTeam,
        loggedInUserId: loggedInUserId,
      ),
      // Large uploads are split among callers (e.g. 1000 leads): load them all, not the default 500
      'limit': '2000',
    });
    final res = await _request('GET', '/leads$q');
    if (!_ok(res)) return null;
    final data = _decodeMap(res);
    final list = data?['leads'];
    if (list is! List) return null;
    return list.whereType<Map>().map((l) => leadFromJson(Map<String, dynamic>.from(l))).toList();
  }

  /// PUT /admin/leads/:id — callers may change status / notes / logAttempt on their own leads.
  static Future<bool> updateLead({
    required String leadId,
    LeadStatus? status,
    String? notes,
    bool logAttempt = false,
  }) async {
    if (leadId.isEmpty) return false;
    final res = await _request('PUT', '/admin/leads/${Uri.encodeComponent(leadId)}', body: {
      if (status != null) 'status': leadStatusToWire(status),
      'notes': ?notes,
      if (logAttempt) 'logAttempt': true,
    });
    return _ok(res);
  }

  // ------------------------------------------------------------------ Recordings

  static Future<List<RecordingModel>?> fetchRecordings({
    String? callerPhone,
    String? callerName,
    String? team,
    String? userId,
    String? loggedInRole,
    String? loggedInTeam,
    String? loggedInUserId,
  }) async {
    final q = _query(_scopeQuery(
      callerPhone: callerPhone,
      callerName: callerName,
      team: team,
      userId: userId,
      loggedInRole: loggedInRole,
      loggedInTeam: loggedInTeam,
      loggedInUserId: loggedInUserId,
    ));
    final res = await _request('GET', '/recordings$q');
    if (!_ok(res)) return null;
    final data = _decodeMap(res);
    final list = data?['recordings'];
    if (list is! List) return null;
    return list.whereType<Map>().map((r) => recordingFromJson(Map<String, dynamic>.from(r), baseUrl)).toList();
  }

  /// Audio URL a media player can open (adds `?token=`).
  static String authorizedMediaUrl(String url) => withTokenQuery(url, _token);

  /// POST /recordings. The server de-duplicates by caller + fileName, so retrying a failed or
  /// timed-out upload with the same fileName never creates a second recording.
  static Future<bool> saveRecording({
    required String callerId,
    required String callerName,
    required String callerPhone,
    required String contactName,
    required String phoneNumber,
    required Duration duration,
    required String fileName,
    required String audioData,
    DateTime? callStartedAt,
    String? type,
    int? simSlot,
  }) async {
    final started = callStartedAt?.toUtc();
    final payload = {
      'callerId': callerId,
      'callerName': callerName,
      'callerPhone': callerPhone,
      'contactName': contactName,
      'phoneNumber': phoneNumber,
      'durationSeconds': duration.inSeconds,
      'fileName': fileName,
      'audioData': audioData,
      if (started != null) 'callStartedAt': started.toIso8601String(),
      if (started != null) 'callLogTimestampMs': started.millisecondsSinceEpoch,
      'type': ?type,
      if (simSlot != null && simSlot > 0) 'simSlot': simSlot,
    };
    final res = await _request('POST', '/recordings', body: payload, timeout: const Duration(seconds: 90));
    return _ok(res);
  }

  static Future<bool> deleteRecording(String recordingId) async {
    final res = await _request('DELETE', '/recordings/${Uri.encodeComponent(recordingId)}');
    return _ok(res);
  }

  static Future<bool> saveRecordingFeedback({
    required String recordingId,
    required int rating,
    required String comment,
    required String commentedBy,
    required String commentedByRole,
  }) async {
    final res = await _request('POST', '/recordings/${Uri.encodeComponent(recordingId)}/comment', body: {
      'rating': rating,
      'comment': comment,
      'commentedBy': commentedBy,
      'commentedByRole': commentedByRole,
    });
    return _ok(res);
  }

  // ------------------------------------------------------------------ Notifications

  static Future<Map<String, dynamic>?> fetchCallerNotifications({String? phone, String? name}) async {
    final q = _query({'phone': phone, 'name': name});
    final res = await _request('GET', '/user/notifications$q');
    if (!_ok(res)) return null;
    return _decodeMap(res);
  }

  static Future<bool> markNotificationRead(String notifId) async {
    final res = await _request('POST', '/user/notifications/${Uri.encodeComponent(notifId)}/read', body: {});
    return _ok(res);
  }

  static Future<bool> markAllNotificationsRead({String? phone, String? name}) async {
    final res = await _request('POST', '/user/notifications/read-all', body: {'phone': phone ?? '', 'name': name ?? ''});
    return _ok(res);
  }

  // ------------------------------------------------------------------ Contacts / users

  static Future<bool> saveContact({required String phoneNumber, required String name, String? notes}) async {
    final res = await _request('POST', '/user/contacts/save', body: {
      'phoneNumber': phoneNumber,
      'name': name,
      'notes': notes ?? '',
    });
    return _ok(res);
  }

  /// POST /admin/users. Never retried automatically (a replay could create the user twice).
  static Future<Map<String, dynamic>> createUser({
    required String name,
    required String email,
    required String phone,
    required String password,
    String role = 'caller',
    String team = 'Telesales Team',
    int dailyTarget = kDefaultDailyTarget,
    String? managerId,
    String? managerName,
  }) async {
    final res = await _request('POST', '/admin/users', body: {
      'name': name,
      'email': email,
      'phone': phone,
      'password': password,
      'role': role,
      'team': team,
      'dailyTarget': dailyTarget,
      'managerId': managerId ?? '',
      'managerName': managerName ?? '',
    });
    if (res == null) {
      return {
        'success': false,
        'message': 'No response from server. Check the user list before trying again — the account may already exist.',
      };
    }
    final data = _decodeMap(res) ?? {};
    if (_ok(res)) {
      return {'success': true, 'message': data['message'] ?? 'User created successfully', 'user': data['user']};
    }
    return {'success': false, 'message': data['message'] ?? 'Failed to create user (HTTP ${res.statusCode})'};
  }
}
