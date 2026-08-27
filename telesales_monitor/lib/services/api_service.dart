import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/call_log_model.dart';
import '../models/employee_model.dart';
import '../models/lead_model.dart';
import '../models/recording_model.dart';

class ApiService {
  // Candidate hosts: LAN IP (192.168.0.29:5004), adb reverse / local, emulator, production
  static final List<String> candidateBaseUrls = [
    'http://192.168.0.29:5004/api',
    'http://127.0.0.1:5004/api',
    'http://10.0.2.2:5004/api',
    'https://telesales.askeva.io/api',
    'http://telesales.askeva.io/api',
    'http://192.168.0.24:5004/api',
    'http://192.168.0.22:5004/api',
  ];

  static String baseUrl = 'http://192.168.0.29:5004/api';

  static void setBaseUrl(String url) {
    baseUrl = url;
  }

  // Helper: Post with automatic host failover
  static Future<http.Response?> _postWithFallback(String path, Map<String, dynamic> body) async {
    final urlsToTry = [baseUrl, ...candidateBaseUrls.where((u) => u != baseUrl)];
    for (final base in urlsToTry) {
      try {
        final res = await http.post(
          Uri.parse('$base$path'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ).timeout(const Duration(milliseconds: 3500));

        if (res.statusCode < 500) {
          baseUrl = base;
          return res;
        }
      } catch (_) {}
    }
    return null;
  }

  // Helper: Get with automatic host failover
  static Future<http.Response?> _getWithFallback(String path) async {
    final urlsToTry = [baseUrl, ...candidateBaseUrls.where((u) => u != baseUrl)];
    for (final base in urlsToTry) {
      try {
        final res = await http.get(
          Uri.parse('$base$path'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(milliseconds: 3500));

        if (res.statusCode < 500) {
          baseUrl = base;
          return res;
        }
      } catch (_) {}
    }
    return null;
  }

  // 1. Sync Batch Calls to MongoDB Backend
  static Future<bool> syncCallLogs(List<CallLogModel> calls, {String callerName = 'Caller Agent', String callerPhone = ''}) async {
    try {
      final payload = {
        'callerId': 'caller_1',
        'callerName': callerName,
        'callerPhone': callerPhone,
        'calls': calls.map((c) => {
          'contactName': c.contactName,
          'phoneNumber': c.phoneNumber,
          'type': c.type.name,
          'timestamp': c.timestamp.toIso8601String(),
          'durationSeconds': c.duration.inSeconds,
          'simSlot': c.simSlot,
          'note': c.note ?? '',
        }).toList(),
      };

      final res = await _postWithFallback('/calls/sync', payload);
      return res != null && (res.statusCode == 200 || res.statusCode == 201);
    } catch (e) {
      debugPrint('ApiService.syncCallLogs notice: $e');
      return false;
    }
  }

  // 2. Fetch Admin Dashboard Telemetry
  static Future<Map<String, dynamic>?> fetchDashboardStats({String? callerPhone, String? callerName, String? team}) async {
    try {
      final queryParams = <String>[];
      if (callerPhone != null && callerPhone.isNotEmpty) queryParams.add('callerPhone=${Uri.encodeComponent(callerPhone)}');
      if (callerName != null && callerName.isNotEmpty) queryParams.add('callerName=${Uri.encodeComponent(callerName)}');
      if (team != null && team.isNotEmpty) queryParams.add('team=${Uri.encodeComponent(team)}');
      final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';

      final res = await _getWithFallback('/dashboard/stats$queryString');
      if (res != null && res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['stats'] as Map<String, dynamic>? ?? data['data'] as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint('ApiService.fetchDashboardStats notice: $e');
    }
    return null;
  }

  // 3. Fetch Team Leaderboard
  static Future<List<EmployeeModel>?> fetchLeaderboard({String? callerPhone, String? callerName, String? team}) async {
    try {
      final queryParams = <String>[];
      if (callerPhone != null && callerPhone.isNotEmpty) queryParams.add('callerPhone=${Uri.encodeComponent(callerPhone)}');
      if (callerName != null && callerName.isNotEmpty) queryParams.add('callerName=${Uri.encodeComponent(callerName)}');
      if (team != null && team.isNotEmpty) queryParams.add('team=${Uri.encodeComponent(team)}');
      final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';

      final res = await _getWithFallback('/employees/leaderboard$queryString');
      if (res != null && res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data['employees'] ?? data['data']) as List<dynamic>;
        return list.map((e) {
          final totalCalls = e['totalCalls'] as int? ?? 0;
          final connectedCalls = e['connectedCalls'] as int? ?? 0;
          final talkTimeSec = e['talkTimeSeconds'] as int? ?? 0;

          return EmployeeModel(
            id: e['id']?.toString() ?? '1',
            name: e['name'] ?? '',
            phone: e['phone'] ?? '',
            role: e['role']?.toString() ?? 'caller',
            totalCalls: totalCalls,
            connectedCalls: connectedCalls,
            totalTalkTime: Duration(seconds: talkTimeSec),
            incomingCalls: (totalCalls * 0.25).toInt(),
            outgoingCalls: (totalCalls * 0.75).toInt(),
            missedCalls: (totalCalls * 0.05).toInt(),
            neverAttendedCalls: (totalCalls * 0.03).toInt(),
            rank: e['rank'] as int? ?? 1,
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('ApiService.fetchLeaderboard notice: $e');
    }
    return null;
  }

  // 4. Fetch CRM Leads from Backend
  static Future<List<LeadModel>?> fetchLeads({String? callerPhone, String? callerName, String? team}) async {
    try {
      final queryParams = <String>[];
      if (callerPhone != null && callerPhone.isNotEmpty) queryParams.add('callerPhone=${Uri.encodeComponent(callerPhone)}');
      if (callerName != null && callerName.isNotEmpty) queryParams.add('callerName=${Uri.encodeComponent(callerName)}');
      if (team != null && team.isNotEmpty) queryParams.add('team=${Uri.encodeComponent(team)}');
      final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';

      final res = await _getWithFallback('/leads$queryString');
      if (res != null && res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = data['leads'] as List<dynamic>;
        return list.map((l) {
          LeadStatus status = LeadStatus.newLead;
          final s = l['status']?.toString();
          if (s == 'interested') {
            status = LeadStatus.interested;
          } else if (s == 'followUp') {
            status = LeadStatus.followUp;
          } else if (s == 'notPickup') {
            status = LeadStatus.notPickup;
          } else if (s == 'won') {
            status = LeadStatus.won;
          } else if (s == 'lost') {
            status = LeadStatus.lost;
          } else if (s == 'renewalFollowUp') {
            status = LeadStatus.renewalFollowUp;
          } else if (s == 'busyOnCall') {
            status = LeadStatus.busyOnCall;
          }

          return LeadModel(
            id: l['id']?.toString() ?? '1',
            name: l['name'] ?? '',
            phone: l['phone'] ?? '',
            status: status,
            attempts: l['attempts'] ?? 0,
            note: l['notes'] ?? '',
            lastCallDate: DateTime.now(),
            dateAdded: DateTime.now(),
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('ApiService.fetchLeads notice: $e');
    }
    return null;
  }

  // 5. Fetch Audio Recordings from Backend
  static Future<List<RecordingModel>?> fetchRecordings({String? callerPhone, String? callerName, String? team}) async {
    try {
      final queryParams = <String>[];
      if (callerPhone != null && callerPhone.isNotEmpty) queryParams.add('callerPhone=${Uri.encodeComponent(callerPhone)}');
      if (callerName != null && callerName.isNotEmpty) queryParams.add('callerName=${Uri.encodeComponent(callerName)}');
      if (team != null && team.isNotEmpty) queryParams.add('team=${Uri.encodeComponent(team)}');
      final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';

      final res = await _getWithFallback('/recordings$queryString');
      if (res != null && res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = data['recordings'] as List<dynamic>;
        return list.map((r) {
          final sec = r['durationSeconds'] as int? ?? 0;
          final rawAudioUrl = r['audioUrl']?.toString() ?? '';
          String fullAudioUrl = rawAudioUrl;
          if (rawAudioUrl.isNotEmpty && rawAudioUrl.startsWith('/')) {
            try {
              final uri = Uri.parse(baseUrl);
              final origin = '${uri.scheme}://${uri.host}:${uri.port}';
              fullAudioUrl = '$origin$rawAudioUrl';
            } catch (_) {
              fullAudioUrl = '$baseUrl$rawAudioUrl';
            }
          }

          DateTime recDate = DateTime.now();
          if (r['createdAt'] != null) {
            recDate = DateTime.tryParse(r['createdAt'].toString())?.toLocal() ?? DateTime.now();
          }

          return RecordingModel(
            id: r['id']?.toString() ?? '1',
            agentName: r['callerName'] ?? 'Caller',
            clientName: r['contactName'] ?? 'Unknown',
            clientPhone: r['phoneNumber'] ?? '+91 98250 12340',
            date: recDate,
            duration: Duration(seconds: sec),
            audioUrl: fullAudioUrl,
            audioData: r['audioData']?.toString(),
            note: r['transcript'] ?? '',
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('ApiService.fetchRecordings notice: $e');
    }
    return null;
  }

  // 6. Save Call Recording into MongoDB Database
  static Future<bool> saveRecording({
    required String callerName,
    required String contactName,
    required String phoneNumber,
    required Duration duration,
    required String dateStr,
    required String timeStr,
    required String fileName,
    String? audioData,
    String? transcript,
  }) async {
    try {
      final payload = {
        'callerName': callerName,
        'contactName': contactName,
        'phoneNumber': phoneNumber,
        'durationSeconds': duration.inSeconds,
        'dateStr': dateStr,
        'timeStr': timeStr,
        'fileName': fileName,
        'audioData': audioData ?? '',
        'transcript': transcript ?? 'Voice audio auto-recorded on hardware SIM ($fileName)',
      };

      final res = await _postWithFallback('/recordings', payload);
      return res != null && (res.statusCode == 200 || res.statusCode == 201);
    } catch (e) {
      debugPrint('ApiService.saveRecording notice: $e');
      return false;
    }
  }

  // 7. Login Admin / Manager via Backend API
  static Future<Map<String, dynamic>?> loginAdmin(String emailOrUsername, String password) async {
    try {
      final res = await _postWithFallback('/auth/admin-login', {
        'email': emailOrUsername,
        'username': emailOrUsername,
        'password': password,
      });
      if (res != null) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('ApiService.loginAdmin error: $e');
    }
    return null;
  }

  // 8. Verify Caller via Backend API (Supports Phone Number, Registered Email or Username)
  static Future<Map<String, dynamic>?> verifyCaller(String phoneOrEmail, {String password = '', int simSlot = 1}) async {
    try {
      final res = await _postWithFallback('/auth/caller-verify', {
        'phoneNumber': phoneOrEmail,
        'email': phoneOrEmail,
        'username': phoneOrEmail,
        'password': password,
        'simSlot': simSlot,
      });
      if (res != null) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('ApiService.verifyCaller error: $e');
    }
    return null;
  }

  // 9. Link / Update Mobile SIM Number for Employee Account
  static Future<Map<String, dynamic>?> linkPhone({required String userId, required String email, required String phone}) async {
    try {
      final res = await _postWithFallback('/auth/link-phone', {
        'userId': userId,
        'email': email,
        'phone': phone,
      });
      if (res != null) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('ApiService.linkPhone error: $e');
    }
    return null;
  }

  // 10. Save Call Quality Rating and Comment for Recording
  static Future<bool> saveRecordingFeedback({
    required String recordingId,
    required int rating,
    required String comment,
    required String commentedBy,
    required String commentedByRole,
  }) async {
    try {
      final res = await _postWithFallback('/admin/recordings/$recordingId/comment', {
        'rating': rating,
        'comment': comment,
        'commentedBy': commentedBy,
        'commentedByRole': commentedByRole,
      });
      return res != null && res.statusCode == 200;
    } catch (e) {
      debugPrint('ApiService.saveRecordingFeedback error: $e');
      return false;
    }
  }

  // 11. Fetch Caller Notifications
  static Future<Map<String, dynamic>?> fetchCallerNotifications({String? phone, String? name}) async {
    try {
      final queryParams = <String, String>{};
      if (phone != null && phone.isNotEmpty) queryParams['phone'] = phone;
      if (name != null && name.isNotEmpty) queryParams['name'] = name;
      final uriStr = Uri(path: '/user/notifications', queryParameters: queryParams.isNotEmpty ? queryParams : null).toString();

      final res = await _getWithFallback(uriStr);
      if (res != null && res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('ApiService.fetchCallerNotifications error: $e');
    }
    return null;
  }

  // 12. Mark Notification as Read
  static Future<bool> markNotificationRead(String notifId) async {
    try {
      final res = await _postWithFallback('/user/notifications/$notifId/read', {});
      return res != null && res.statusCode == 200;
    } catch (e) {
      debugPrint('ApiService.markNotificationRead error: $e');
      return false;
    }
  }

  // 13. Mark All Notifications as Read
  static Future<bool> markAllNotificationsRead({String? phone, String? name}) async {
    try {
      final res = await _postWithFallback('/user/notifications/read-all', {
        'phone': phone ?? '',
        'name': name ?? '',
      });
      return res != null && res.statusCode == 200;
    } catch (e) {
      debugPrint('ApiService.markAllNotificationsRead error: $e');
      return false;
    }
  }

  // 14. Save or Update Contact Name in CRM & Database
  static Future<bool> saveContact({
    required String phoneNumber,
    required String name,
    String? notes,
  }) async {
    try {
      final res = await _postWithFallback('/user/contacts/save', {
        'phoneNumber': phoneNumber,
        'name': name,
        'notes': notes ?? '',
      });
      return res != null && res.statusCode == 200;
    } catch (e) {
      debugPrint('ApiService.saveContact error: $e');
      return false;
    }
  }

  // 15. Create New User / Caller (Admin & Manager)
  static Future<Map<String, dynamic>> createUser({
    required String name,
    required String email,
    required String phone,
    required String password,
    String role = 'caller',
    String team = 'Telesales Team',
    int dailyTarget = 100,
    String? managerId,
    String? managerName,
  }) async {
    try {
      final res = await _postWithFallback('/admin/users', {
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
      if (res != null && (res.statusCode == 200 || res.statusCode == 201)) {
        final data = jsonDecode(res.body);
        return {'success': true, 'message': data['message'] ?? 'User created successfully', 'user': data['user']};
      }
      final errorData = res != null ? jsonDecode(res.body) : null;
      return {'success': false, 'message': errorData?['message'] ?? 'Failed to create user'};
    } catch (e) {
      debugPrint('ApiService.createUser error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }
}
