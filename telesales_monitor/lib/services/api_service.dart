import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/call_log_model.dart';
import '../models/employee_model.dart';
import '../models/lead_model.dart';
import '../models/recording_model.dart';

class ApiService {
  // Candidate hosts: Production Subdomain (telesales.askeva.io), LAN IP, adb reverse / local, emulator
  static final List<String> candidateBaseUrls = [
    'https://telesales.askeva.io/api',
    'http://telesales.askeva.io/api',
    'http://192.168.0.24:5000/api',
    'http://127.0.0.1:5000/api',
    'http://10.0.2.2:5000/api',
    'http://192.168.0.22:5000/api',
  ];

  static String baseUrl = 'https://telesales.askeva.io/api';

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
        ).timeout(const Duration(milliseconds: 2500));

        if (res.statusCode == 200 || res.statusCode == 201) {
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
        ).timeout(const Duration(milliseconds: 2500));

        if (res.statusCode == 200) {
          baseUrl = base;
          return res;
        }
      } catch (_) {}
    }
    return null;
  }

  // 1. Sync Batch Calls to MongoDB Backend
  static Future<bool> syncCallLogs(List<CallLogModel> calls, {String callerName = 'Priyanka Panchal', String callerPhone = '+91 98250 12340'}) async {
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
  static Future<Map<String, dynamic>?> fetchDashboardStats() async {
    try {
      final res = await _getWithFallback('/dashboard/stats');
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
  static Future<List<EmployeeModel>?> fetchLeaderboard() async {
    try {
      final res = await _getWithFallback('/employees/leaderboard');
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
  static Future<List<LeadModel>?> fetchLeads() async {
    try {
      final res = await _getWithFallback('/leads');
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
  static Future<List<RecordingModel>?> fetchRecordings() async {
    try {
      final res = await _getWithFallback('/recordings');
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
      if (res != null && (res.statusCode == 200 || res.statusCode == 201)) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('ApiService.loginAdmin error: $e');
    }
    return null;
  }

  // 8. Verify Caller via Backend API
  static Future<Map<String, dynamic>?> verifyCaller(String phoneOrUsername, {int simSlot = 1}) async {
    try {
      final res = await _postWithFallback('/auth/caller-verify', {
        'phoneNumber': phoneOrUsername,
        'simSlot': simSlot,
      });
      if (res != null && (res.statusCode == 200 || res.statusCode == 201)) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('ApiService.verifyCaller error: $e');
    }
    return null;
  }
}
