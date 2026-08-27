import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/call_log_model.dart';
import '../models/lead_model.dart';
import '../models/employee_model.dart';
import '../models/recording_model.dart';
import '../models/sim_card_info.dart';
import '../models/notification_model.dart';
import '../services/api_service.dart';

enum UserRole { manager, caller }
enum SimTrackingMode { sim1Only, sim2Only, bothSims }

class ScheduledCallback {
  final String id;
  final String name;
  final String phone;
  DateTime scheduledTime;
  final String note;
  bool isSnoozed;

  ScheduledCallback({
    required this.id,
    required this.name,
    required this.phone,
    required this.scheduledTime,
    required this.note,
    this.isSnoozed = false,
  });
}

class TeleProvider extends ChangeNotifier {
  static const MethodChannel _telephonyChannel = MethodChannel('com.askeva.telesales/telephony');

  UserRole _currentRole = UserRole.caller;
  bool _isLoggedIn = false;
  bool _setupCompleted = false;
  int _activeTabIndex = 1;
  DateTime? _loginSessionTimestamp;

  // Real Dynamic SIM Detection
  List<SimCardInfo> _detectedSims = [];
  SimTrackingMode _simTrackingMode = SimTrackingMode.bothSims;
  String _verifiedTrackingNumber = '';
  String _callerName = '';

  UserRole get currentRole => _currentRole;
  bool get isLoggedIn => _isLoggedIn;
  bool get setupCompleted => _setupCompleted;
  int get activeTabIndex => _activeTabIndex;
  DateTime? get loginSessionTimestamp => _loginSessionTimestamp;
  List<SimCardInfo> get detectedSims => _detectedSims;
  bool get isLoadingSims => false;
  SimTrackingMode get simTrackingMode => _simTrackingMode;
  String get verifiedTrackingNumber => _verifiedTrackingNumber;
  String get callerName => _callerName;

  String get currentUserName {
    if (_callerName.isNotEmpty && _callerName != 'Caller Agent') {
      return _callerName;
    }
    if (_verifiedTrackingNumber.isNotEmpty) {
      return _verifiedTrackingNumber;
    }
    return _currentRole == UserRole.manager ? 'ADMIN' : 'CALLER AGENT';
  }

  void setCallerName(String name) {
    _callerName = name;
    _savePreferences();
    notifyListeners();
  }

  TeleProvider() {
    _initChannelListener();
    _loadPreferencesAndState();
  }

  bool _autoRecordEnabled = true;
  bool get autoRecordEnabled => _autoRecordEnabled;

  bool _isCallRecordingActive = false;
  bool get isCallRecordingActive => _isCallRecordingActive;

  void toggleAutoRecord() {
    _autoRecordEnabled = !_autoRecordEnabled;
    _telephonyChannel.invokeMethod('setAutoRecord', {'enabled': _autoRecordEnabled});
    _savePreferences();
    notifyListeners();
  }

  void _initChannelListener() {
    _telephonyChannel.setMethodCallHandler((call) async {
      if (call.method == 'onCallRecordingStatus') {
        final active = (call.arguments is Map) ? call.arguments['isRecording'] == true : false;
        _isCallRecordingActive = active;
        notifyListeners();
      } else if (call.method == 'onCallStateChanged') {
        _isCallRecordingActive = false;
        await fetchDeviceCallLogs();
      } else if (call.method == 'onRecordingSaved') {
        _isCallRecordingActive = false;
        final map = (call.arguments is Map) ? call.arguments as Map : {};
        final fileName = map['fileName']?.toString() ?? '';
        final filePath = map['filePath']?.toString() ?? '';
        final audioData = map['audioData']?.toString() ?? '';
        final durSec = (map['durationSeconds'] is int) ? map['durationSeconds'] as int : 5;
        final dur = Duration(seconds: durSec);

        final agent = _callerName.isNotEmpty ? _callerName : (_verifiedTrackingNumber.isNotEmpty ? _verifiedTrackingNumber : 'Caller Agent');
        final contact = _callLogs.isNotEmpty ? _callLogs.first.contactName : 'Recent Call';
        final phone = _callLogs.isNotEmpty ? _callLogs.first.phoneNumber : '+91 98250 12340';

        final newRec = RecordingModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          agentName: agent,
          clientName: contact,
          clientPhone: phone,
          date: DateTime.now(),
          duration: dur,
          filePath: filePath,
          audioData: audioData,
          note: 'Real Recorded Audio ($fileName)',
        );
        _recordings.insert(0, newRec);
        notifyListeners();

        // Push directly to MongoDB Backend with real audio binary
        ApiService.saveRecording(
          callerName: agent,
          contactName: contact,
          phoneNumber: phone,
          duration: dur,
          dateStr: 'Today',
          timeStr: '${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
          fileName: fileName,
          audioData: audioData,
          transcript: 'Real voice audio recorded via hardware microphone ($fileName)',
        ).then((_) => fetchBackendData());
      }
    });
  }

  String _authToken = '';
  String get authToken => _authToken;

  Future<void> _loadPreferencesAndState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isLoggedIn = prefs.getBool('is_logged_in') ?? false;
      _setupCompleted = prefs.getBool('setup_completed') ?? false;
      _authToken = prefs.getString('auth_token') ?? '';
      _verifiedTrackingNumber = prefs.getString('verified_tracking_number') ?? '';
      _callerName = prefs.getString('caller_name') ?? '';
      _autoRecordEnabled = prefs.getBool('auto_record_enabled') ?? true;
      final roleStr = prefs.getString('user_role');
      if (roleStr != null) {
        _currentRole = UserRole.values.firstWhere((r) => r.name == roleStr, orElse: () => UserRole.caller);
      }
      final modeStr = prefs.getString('sim_tracking_mode');
      if (modeStr != null) {
        _simTrackingMode = SimTrackingMode.values.firstWhere(
          (m) => m.name == modeStr,
          orElse: () => SimTrackingMode.bothSims,
        );
      }
      final sessionMs = prefs.getInt('initial_setup_timestamp_ms') ?? prefs.getInt('login_session_timestamp_ms');
      if (sessionMs != null) {
        _loginSessionTimestamp = DateTime.fromMillisecondsSinceEpoch(sessionMs);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading saved preferences: $e');
    }
    await fetchDeviceSims();
    await fetchDeviceCallLogs();
    await fetchBackendData();
    _startPeriodicSyncTimer();
  }

  Timer? _syncPollingTimer;

  void _startPeriodicSyncTimer() {
    _syncPollingTimer?.cancel();
    _syncPollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_isLoggedIn) {
        fetchNotifications();
      }
    });
  }

  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', _isLoggedIn);
      await prefs.setBool('setup_completed', _setupCompleted);
      if (_authToken.isEmpty && _isLoggedIn) {
        _authToken = 'token_${_currentRole.name}_${DateTime.now().millisecondsSinceEpoch}';
      }
      await prefs.setString('auth_token', _authToken);
      await prefs.setString('verified_tracking_number', _verifiedTrackingNumber);
      await prefs.setString('caller_name', _callerName);
      await prefs.setBool('auto_record_enabled', _autoRecordEnabled);
      await prefs.setString('sim_tracking_mode', _simTrackingMode.name);
      await prefs.setString('user_role', _currentRole.name);
      if (_loginSessionTimestamp != null) {
        await prefs.setInt('initial_setup_timestamp_ms', _loginSessionTimestamp!.millisecondsSinceEpoch);
        await prefs.setInt('login_session_timestamp_ms', _loginSessionTimestamp!.millisecondsSinceEpoch);
      }
    } catch (e) {
      debugPrint('Error saving preferences: $e');
    }
  }

  Map<String, dynamic>? _backendStats;
  Map<String, dynamic>? get backendStats => _backendStats;
  List<EmployeeModel> _teamEmployees = [];
  String _selectedTeamFilter = 'ALL';
  String get selectedTeamFilter => _selectedTeamFilter;
  List<String> _availableTeams = ['ALL', 'Telesales Team', 'Management'];
  List<String> get availableTeams => _availableTeams;

  void setTeamFilter(String team) {
    _selectedTeamFilter = team;
    notifyListeners();
    fetchBackendData();
  }

  Future<void> fetchBackendData() async {
    try {
      String? phoneParam;
      String? nameParam;
      String? teamParam;

      if (_currentRole == UserRole.caller) {
        phoneParam = _verifiedTrackingNumber;
        nameParam = _callerName;
      } else {
        if (_selectedTeamFilter != 'ALL') {
          teamParam = _selectedTeamFilter;
        }
      }

      final stats = await ApiService.fetchDashboardStats(callerPhone: phoneParam, callerName: nameParam, team: teamParam);
      if (stats != null) {
        _backendStats = stats;
        if (stats['teams'] != null) {
          final rawTeams = List<String>.from((stats['teams'] as List).map((t) => t.toString()));
          final filtered = rawTeams.where((t) => t != 'ALL' && t != 'ALL TEAMS').toList();
          _availableTeams = ['ALL', ...filtered];
        }
      }
      final emps = await ApiService.fetchLeaderboard(callerPhone: phoneParam, callerName: nameParam, team: teamParam);
      _teamEmployees = emps ?? [];

      final recs = await ApiService.fetchRecordings(callerPhone: phoneParam, callerName: nameParam, team: teamParam);
      if (recs != null) {
        for (var newR in recs) {
          final existingIndex = _recordings.indexWhere((r) =>
            r.id == newR.id || (r.filePath.isNotEmpty && newR.audioUrl.contains(r.filePath.split(RegExp(r'[/\\]')).last))
          );
          if (existingIndex != -1 && _recordings[existingIndex].filePath.isNotEmpty) {
            newR.filePath = _recordings[existingIndex].filePath;
          }
        }
        _recordings.clear();
        _recordings.addAll(recs);
      } else {
        _recordings.clear();
      }

      await fetchNotifications();
      notifyListeners();
    } catch (e) {
      debugPrint('Backend fetch notice: $e');
    }
  }

  // Caller Notifications
  final List<NotificationItem> _notifications = [];
  int _unreadNotificationCount = 0;
  List<NotificationItem> get notifications => _notifications;
  int get unreadNotificationCount => _unreadNotificationCount;

  Future<void> fetchNotifications() async {
    try {
      final res = await ApiService.fetchCallerNotifications(
        phone: _verifiedTrackingNumber,
        name: _callerName,
      );
      if (res != null && res['success'] == true) {
        _unreadNotificationCount = (res['unreadCount'] is int) ? res['unreadCount'] as int : 0;
        if (res['notifications'] is List) {
          _notifications.clear();
          for (var item in res['notifications']) {
            if (item is Map<String, dynamic>) {
              _notifications.add(NotificationItem.fromJson(item));
            }
          }
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('fetchNotifications error: $e');
    }
  }

  Future<void> markNotificationRead(String notifId) async {
    final idx = _notifications.indexWhere((n) => n.id == notifId);
    if (idx != -1 && !_notifications[idx].isRead) {
      _notifications[idx].isRead = true;
      if (_unreadNotificationCount > 0) _unreadNotificationCount--;
      notifyListeners();
    }
    await ApiService.markNotificationRead(notifId);
  }

  Future<void> markAllNotificationsRead() async {
    for (var n in _notifications) {
      n.isRead = true;
    }
    _unreadNotificationCount = 0;
    notifyListeners();
    await ApiService.markAllNotificationsRead(phone: _verifiedTrackingNumber, name: _callerName);
  }

  Future<bool> requestNativePermissions() async {
    try {
      final bool? granted = await _telephonyChannel.invokeMethod('requestPermissions');
      await fetchDeviceSims();
      await fetchDeviceCallLogs();
      return granted ?? false;
    } catch (e) {
      debugPrint('Error requesting native permissions: $e');
      await fetchDeviceSims();
      await fetchDeviceCallLogs();
      return false;
    }
  }

  // 100% Real Live Call Logs from Phone Hardware
  final List<CallLogModel> _callLogs = [];
  List<CallLogModel> get allCallLogs => _callLogs;

  Future<void> fetchDeviceCallLogs() async {
    try {
      final List<dynamic>? rawLogs = await _telephonyChannel.invokeMethod('getCallLogs');
      if (rawLogs != null) {
        final List<CallLogModel> realLogs = [];
        for (var map in rawLogs) {
          if (map is Map<dynamic, dynamic>) {
            final typeStr = map['type'] as String? ?? 'incoming';
            CallType cType = CallType.incoming;
            if (typeStr == 'outgoing') cType = CallType.outgoing;
            if (typeStr == 'missed') cType = CallType.missed;
            if (typeStr == 'rejected') cType = CallType.rejected;

            final int durationSec = (map['duration'] is int)
                ? map['duration'] as int
                : (map['duration'] is double)
                    ? (map['duration'] as double).toInt()
                    : 0;

            final int timestampMs = (map['timestamp'] is int)
                ? map['timestamp'] as int
                : DateTime.now().millisecondsSinceEpoch;

            if (_loginSessionTimestamp != null && timestampMs < _loginSessionTimestamp!.millisecondsSinceEpoch - 5000) {
              continue; // Only track and sync calls made after active user login
            }

            realLogs.add(
              CallLogModel(
                id: map['id']?.toString() ?? UniqueKey().toString(),
                contactName: (map['contactName'] as String?)?.isNotEmpty == true
                    ? map['contactName'] as String
                    : 'Unknown',
                phoneNumber: map['phoneNumber']?.toString() ?? '',
                type: cType,
                duration: Duration(seconds: durationSec),
                timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
                simSlot: map['simSlot'] as int? ?? 1,
              ),
            );
          }
        }
        _callLogs.clear();
        _callLogs.addAll(realLogs);
        _syncLeadsFromCallLogs();
        _syncCallbacksFromCallLogs();
        if (_currentRole == UserRole.caller) {
          ApiService.syncCallLogs(_callLogs, callerName: _callerName, callerPhone: _verifiedTrackingNumber);
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching device call logs: $e');
    }
  }

  Future<void> fetchDeviceSims() async {
    try {
      final List<dynamic>? rawList = await _telephonyChannel.invokeMethod('getSimCards');
      if (rawList != null && rawList.isNotEmpty) {
        _detectedSims = rawList
            .map((e) => SimCardInfo.fromMap(e as Map<dynamic, dynamic>))
            .toList();
        if (_verifiedTrackingNumber.isEmpty && _detectedSims.isNotEmpty) {
          _verifiedTrackingNumber = _detectedSims[0].phoneNumber;
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Platform channel getSimCards info: $e');
    }
  }

  Future<Map<String, dynamic>> verifyRegisteredSimCard(String registeredPhone) async {
    await fetchDeviceSims();
    final cleanReg = registeredPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final last10Reg = cleanReg.length >= 10 ? cleanReg.substring(cleanReg.length - 10) : cleanReg;

    if (last10Reg.length != 10) {
      return {'isValid': true};
    }

    if (_detectedSims.isNotEmpty) {
      bool simMatched = false;
      bool hasReadableSimPhone = false;

      for (var sim in _detectedSims) {
        final cleanSim = sim.phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
        final last10Sim = cleanSim.length >= 10 ? cleanSim.substring(cleanSim.length - 10) : cleanSim;
        if (last10Sim.length >= 10) {
          hasReadableSimPhone = true;
          if (last10Sim == last10Reg) {
            simMatched = true;
            break;
          }
        }
      }

      if (hasReadableSimPhone && !simMatched) {
        return {
          'isValid': false,
          'message': 'Device SIM Validation Failed: The registered SIM card (+91 $last10Reg) is not inserted in this mobile phone. Please insert your registered SIM card to proceed.'
        };
      }
    }
    return {'isValid': true};
  }

  Future<Map<String, dynamic>> validateAndSetTrackingNumber(String inputPhone, int slotIndex) async {
    final clean = inputPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final last10 = clean.length >= 10 ? clean.substring(clean.length - 10) : clean;

    if (last10.length != 10 || !RegExp(r'^[6-9]\d{9}$').hasMatch(last10)) {
      return {'isValid': false, 'message': 'Please enter a valid 10-digit mobile number.'};
    }
    try {
      final verifyRes = await ApiService.checkPhoneRegistered(last10);
      if (verifyRes == null || verifyRes['success'] != true) {
        return {
          'isValid': false,
          'message': verifyRes?['message']?.toString() ?? 'Mobile number \'$last10\' is not registered in the database. Please contact your manager or admin to add your account.'
        };
      }
      _callerName = verifyRes['user']?['name']?.toString() ?? _callerName;
    } catch (e) {
      debugPrint('DB verification error: $e');
      return {
        'isValid': false,
        'message': 'Failed to connect to server. Please check your internet connection.'
      };
    }

    _verifiedTrackingNumber = last10;
    _simTrackingMode = slotIndex == 0 ? SimTrackingMode.sim1Only : SimTrackingMode.sim2Only;
    _setupCompleted = true;
    _isLoggedIn = false;
    await _savePreferences();
    notifyListeners();
    return {
      'isValid': true,
      'formattedNumber': _verifiedTrackingNumber,
      'userName': _callerName,
      'message': '✓ SIM ${slotIndex + 1} connected and verified for $_callerName ($last10)!'
    };
  }

  String get activeSimLabel {
    if (_detectedSims.isEmpty) return 'TRACKING: ALL CALLS';
    switch (_simTrackingMode) {
      case SimTrackingMode.sim1Only:
        final s1 = _detectedSims.isNotEmpty ? _detectedSims[0].displayName : 'SIM 1';
        return 'TRACKING: $s1';
      case SimTrackingMode.sim2Only:
        final s2 = _detectedSims.length > 1 ? _detectedSims[1].displayName : 'SIM 2';
        return 'TRACKING: $s2';
      case SimTrackingMode.bothSims:
        return 'TRACKING: ALL DETECTED SIMs';
    }
  }

  void completeSetup({required SimTrackingMode mode, String? verifiedNumber, String? callerName}) {
    _simTrackingMode = mode;
    if (verifiedNumber != null && verifiedNumber.isNotEmpty) {
      _verifiedTrackingNumber = verifiedNumber;
    }
    if (callerName != null && callerName.isNotEmpty) {
      _callerName = callerName;
    }
    _setupCompleted = true;
    _isLoggedIn = true;
    _loginSessionTimestamp ??= DateTime.now();
    _savePreferences();
    notifyListeners();
  }

  void setSimTrackingMode(SimTrackingMode mode) {
    _simTrackingMode = mode;
    _savePreferences();
    notifyListeners();
  }

  void purgeUserSession() {
    _isLoggedIn = false;
    _setupCompleted = true; // Never ask for initial setup again
    _authToken = '';
    _activeTabIndex = 0;
    _savePreferences();
    notifyListeners();
  }

  Future<Map<String, dynamic>> performLogin({
    required String username,
    required String password,
    required UserRole role,
  }) async {
    try {
      if (role == UserRole.manager) {
        final res = await ApiService.loginAdmin(username, password);
        if (res != null && res['success'] == true) {
          final user = res['user'] as Map<String, dynamic>?;
          if (user != null) {
            if (user['name'] != null) _callerName = user['name'].toString();
            if (user['email'] != null) _verifiedTrackingNumber = user['email'].toString();
          }
          _currentRole = UserRole.manager;
          _isLoggedIn = true;
          _setupCompleted = true;
          _loginSessionTimestamp ??= DateTime.now();
          _savePreferences();
          await fetchBackendData();
          notifyListeners();
          return {'success': true, 'message': 'Admin authentication successful'};
        }
        return {'success': false, 'message': res?['message']?.toString() ?? 'Account not registered in DB employees table or incorrect password.'};
      } else {
        final res = await ApiService.verifyCaller(username, password: password);
        if (res != null && res['success'] == true) {
          final user = res['user'] as Map<String, dynamic>?;
          String regPhone = '';
          if (user != null) {
            if (user['name'] != null) _callerName = user['name'].toString();
            if (user['phone'] != null && user['phone'].toString().isNotEmpty) {
              _verifiedTrackingNumber = user['phone'].toString();
              regPhone = user['phone'].toString();
            }
          }

          // If logged in via Email ID with no registered phone in DB, ask for mobile number verification
          if (regPhone.isEmpty) {
            return {
              'success': false,
              'requiresPhoneInput': true,
              'user': user,
              'message': 'Logged in via Email. Please enter your mobile SIM number inserted in this device.'
            };
          }

          // Hardware SIM Card Match Check on Phone
          final simCheck = await verifyRegisteredSimCard(regPhone);
          if (simCheck['isValid'] == false) {
            return {'success': false, 'message': simCheck['message']};
          }

          _currentRole = UserRole.caller;
          _isLoggedIn = true;
          _setupCompleted = true;
          _loginSessionTimestamp ??= DateTime.now();
          _savePreferences();
          await fetchDeviceCallLogs();
          await fetchBackendData();
          notifyListeners();
          return {'success': true, 'message': 'Caller verified successfully'};
        }
        return {'success': false, 'message': res?['message']?.toString() ?? 'Caller account not registered in DB employees table or incorrect password.'};
      }
    } catch (e) {
      debugPrint('TeleProvider.performLogin notice: $e');
    }
    return {'success': false, 'message': 'Could not reach server. Check backend connection.'};
  }

  Future<Map<String, dynamic>> linkAndVerifySimPhone({
    required String userId,
    required String email,
    required String inputPhone,
  }) async {
    final clean = inputPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final last10 = clean.length >= 10 ? clean.substring(clean.length - 10) : clean;
    if (last10.length != 10 || !RegExp(r'^[6-9]\d{9}$').hasMatch(last10)) {
      return {'success': false, 'message': 'Please enter a valid 10-digit mobile number.'};
    }

    final formattedPhone = '+91 $last10';

    // 1. Verify against physical SIM card hardware on phone
    final simCheck = await verifyRegisteredSimCard(formattedPhone);
    if (simCheck['isValid'] == false) {
      return {'success': false, 'message': simCheck['message']};
    }

    // 2. Link phone number in MongoDB database
    final linkRes = await ApiService.linkPhone(userId: userId, email: email, phone: formattedPhone);
    if (linkRes != null && linkRes['success'] == true) {
      _verifiedTrackingNumber = formattedPhone;
      _currentRole = UserRole.caller;
      _isLoggedIn = true;
      _setupCompleted = true;
      _loginSessionTimestamp ??= DateTime.now();
      _savePreferences();
      await fetchDeviceCallLogs();
      await fetchBackendData();
      notifyListeners();
      return {'success': true, 'message': 'Mobile SIM number linked and verified successfully!'};
    }

    return {'success': false, 'message': linkRes?['message']?.toString() ?? 'Failed to link mobile number in database.'};
  }

  void setRole(UserRole role) {
    _currentRole = role;
    _isLoggedIn = true;
    _setupCompleted = true;
    _activeTabIndex = 0;
    _loginSessionTimestamp ??= DateTime.now();
    _savePreferences();
    notifyListeners();
  }

  void logout() {
    purgeUserSession();
  }

  void setTabIndex(int index) {
    _activeTabIndex = index;
    notifyListeners();
  }

  // Filtered by active SIM Slot
  List<CallLogModel> get simTrackedCallLogs {
    switch (_simTrackingMode) {
      case SimTrackingMode.sim1Only:
        return _callLogs.where((c) => c.simSlot == 1).toList();
      case SimTrackingMode.sim2Only:
        return _callLogs.where((c) => c.simSlot == 2).toList();
      case SimTrackingMode.bothSims:
        return _callLogs;
    }
  }

  String _callFilter = 'ALL';
  String get callFilter => _callFilter;
  void setCallFilter(String filter) {
    _callFilter = filter;
    notifyListeners();
  }

  List<CallLogModel> get filteredCallLogs {
    final list = simTrackedCallLogs;
    if (_callFilter == 'ALL') return list;
    if (_callFilter == 'INCOMING') {
      return list.where((c) => c.type == CallType.incoming).toList();
    }
    if (_callFilter == 'OUTGOING') {
      return list.where((c) => c.type == CallType.outgoing).toList();
    }
    if (_callFilter == 'MISSED') {
      return list.where((c) => c.type == CallType.missed).toList();
    }
    if (_callFilter == 'REJECTED') {
      return list.where((c) => c.type == CallType.rejected).toList();
    }
    if (_callFilter == 'NEVER' || _callFilter == 'NO_PICKUP') {
      return list.where((c) => c.duration.inSeconds == 0).toList();
    }
    return list;
  }

  // Telemetry Aggregates
  int get trackedTotalCalls => simTrackedCallLogs.length;
  int get trackedConnectedCalls => simTrackedCallLogs.where((c) => c.duration.inSeconds > 0).length;
  int get trackedIncomingCalls => simTrackedCallLogs.where((c) => c.type == CallType.incoming).length;
  int get trackedOutgoingCalls => simTrackedCallLogs.where((c) => c.type == CallType.outgoing).length;
  int get trackedMissedCalls => simTrackedCallLogs.where((c) => c.type == CallType.missed).length;
  int get trackedNeverAttendedCalls => simTrackedCallLogs.where((c) => c.type == CallType.rejected || c.duration.inSeconds == 0).length;

  Duration get trackedTotalTalkTime {
    var totalSeconds = 0;
    for (var c in simTrackedCallLogs) {
      totalSeconds += c.duration.inSeconds;
    }
    return Duration(seconds: totalSeconds);
  }

  String get trackedTalkTimeFormatted {
    final h = trackedTotalTalkTime.inHours;
    final m = trackedTotalTalkTime.inMinutes % 60;
    final s = trackedTotalTalkTime.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  // Real Dynamic Leads derived from actual phone contacts and calls
  final List<LeadModel> _leads = [];
  List<LeadModel> get leads => _leads;

  void _syncLeadsFromCallLogs() {
    final Map<String, LeadModel> uniqueClients = {};
    for (var call in _callLogs) {
      if (call.phoneNumber.isNotEmpty && !uniqueClients.containsKey(call.phoneNumber)) {
        LeadStatus status = LeadStatus.other;
        if (call.duration.inMinutes >= 5) {
          status = LeadStatus.won;
        } else if (call.duration.inSeconds > 60) {
          status = LeadStatus.interested;
        } else if (call.type == CallType.missed || call.type == CallType.rejected) {
          status = LeadStatus.followUp;
        }

        uniqueClients[call.phoneNumber] = LeadModel(
          id: call.id,
          name: call.contactName,
          phone: call.phoneNumber,
          status: status,
          attempts: 1,
          dateAdded: call.timestamp,
          lastCallDate: call.timestamp,
          note: call.note ?? (status == LeadStatus.won ? 'Order inquiry' : 'Recent phone dial'),
        );
      }
    }
    _leads.clear();
    _leads.addAll(uniqueClients.values);
  }

  String _leadFilter = 'ALL';
  String get leadFilter => _leadFilter;
  void setLeadFilter(String filter) {
    _leadFilter = filter;
    notifyListeners();
  }

  List<LeadModel> get filteredLeads {
    if (_leadFilter == 'ALL') return _leads;
    if (_leadFilter == 'WON') return _leads.where((l) => l.status == LeadStatus.won).toList();
    if (_leadFilter == 'INTERESTED') return _leads.where((l) => l.status == LeadStatus.interested).toList();
    if (_leadFilter == 'FOLLOW-UP') return _leads.where((l) => l.status == LeadStatus.followUp).toList();
    return _leads;
  }

  void updateLeadStatus(String leadId, LeadStatus newStatus) {
    final idx = _leads.indexWhere((l) => l.id == leadId);
    if (idx != -1) {
      _leads[idx].status = newStatus;
      notifyListeners();
    }
  }

  void addLeadNote(String leadId, String newNote) {
    final idx = _leads.indexWhere((l) => l.id == leadId);
    if (idx != -1) {
      _leads[idx].note = newNote;
      notifyListeners();
    }
  }

  // Scheduled Callbacks (100% Dynamic)
  final List<ScheduledCallback> _callbacks = [];

  List<ScheduledCallback> get callbacks => _callbacks;

  void _syncCallbacksFromCallLogs() {
    final Set<String> existingPhones = _callbacks.map((c) => c.phone).toSet();
    for (var call in _callLogs) {
      if ((call.type == CallType.missed || call.type == CallType.rejected) &&
          call.phoneNumber.isNotEmpty &&
          !existingPhones.contains(call.phoneNumber)) {
        _callbacks.add(
          ScheduledCallback(
            id: 'cb_${call.id}',
            name: call.contactName != 'Unknown' ? call.contactName : call.phoneNumber,
            phone: call.phoneNumber,
            scheduledTime: DateTime.now().add(Duration(hours: (_callbacks.length + 1) * 2)),
            note: 'Missed call follow-up required',
          ),
        );
        existingPhones.add(call.phoneNumber);
      }
    }
  }

  void addScheduledCallback({
    required String name,
    required String phone,
    required DateTime scheduledTime,
    required String note,
  }) {
    _callbacks.insert(
      0,
      ScheduledCallback(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        phone: phone,
        scheduledTime: scheduledTime,
        note: note.isNotEmpty ? note : 'Follow-up call scheduled',
      ),
    );
    notifyListeners();
  }

  void snoozeCallback(String id) {
    final idx = _callbacks.indexWhere((c) => c.id == id);
    if (idx != -1) {
      _callbacks[idx].isSnoozed = !_callbacks[idx].isSnoozed;
      _callbacks[idx].scheduledTime = _callbacks[idx].scheduledTime.add(const Duration(minutes: 30));
      notifyListeners();
    }
  }

  // Employees & Leaderboard (Strict Live DB Data)
  List<EmployeeModel> get employees => _teamEmployees;

  EmployeeModel? _selectedEmployee;
  EmployeeModel? get selectedEmployee => _selectedEmployee;
  void selectEmployee(EmployeeModel? emp) {
    _selectedEmployee = emp;
    notifyListeners();
  }

  // Recordings
  final List<RecordingModel> _recordings = [];
  List<RecordingModel> get recordings => _recordings;
  Timer? _recordingTimer;

  Future<void> startTestRecording() async {
    _isCallRecordingActive = true;
    notifyListeners();
    try {
      await _telephonyChannel.invokeMethod('startTestRecording');
    } catch (e) {
      debugPrint('startTestRecording channel fallback: $e');
    }
  }

  Future<void> stopTestRecording() async {
    _isCallRecordingActive = false;
    notifyListeners();
    try {
      await _telephonyChannel.invokeMethod('stopTestRecording');
    } catch (e) {
      debugPrint('stopTestRecording error: $e');
    }
  }

  void toggleRecordingPlayback(String id) {
    for (var r in _recordings) {
      if (r.id == id) {
        r.isPlaying = !r.isPlaying;
        if (r.isPlaying) {
          _telephonyChannel.invokeMethod('playAudio', {
            'filePath': r.filePath,
            'audioUrl': r.audioUrl,
            'audioData': r.audioData ?? '',
          });
          _startRecordingSimulation(r);
        } else {
          _telephonyChannel.invokeMethod('stopAudio');
          _recordingTimer?.cancel();
        }
      } else {
        r.isPlaying = false;
      }
    }
    notifyListeners();
  }

  void _startRecordingSimulation(RecordingModel r) {
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (!r.isPlaying) {
        timer.cancel();
        return;
      }
      r.progress += 0.05;
      if (r.progress >= 1.0) {
        r.progress = 0.0;
        r.isPlaying = false;
        timer.cancel();
      }
      notifyListeners();
    });
  }

  // Direct Telephony Actions
  Future<void> makeDirectCall(String phone, {int slot = 0}) async {
    try {
      await _telephonyChannel.invokeMethod('directCall', {
        'phoneNumber': phone,
        'slotIndex': slot,
      });
    } catch (e) {
      launchCall(phone);
    }
  }

  Future<void> launchCall(String phone) async {
    final clean = phone.trim();
    if (clean.isEmpty) return;
    try {
      await makeDirectCall(clean, slot: _simTrackingMode == SimTrackingMode.sim2Only ? 1 : 0);
    } catch (_) {
      final uri = Uri.parse('tel:$clean');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> launchWhatsApp(String phone, {String text = 'Hello from Telesales team!'}) async {
    var cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPhone.length == 10) {
      cleanPhone = '91$cleanPhone';
    }
    if (cleanPhone.isEmpty) return;

    final encodedText = Uri.encodeComponent(text);
    final nativeUri = Uri.parse('whatsapp://send?phone=$cleanPhone&text=$encodedText');
    try {
      if (await canLaunchUrl(nativeUri)) {
        await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (e) {
      debugPrint('WhatsApp native error: $e');
    }

    final webUri = Uri.parse('https://api.whatsapp.com/send?phone=$cleanPhone&text=$encodedText');
    try {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('WhatsApp web fallback error: $e');
    }
  }

  Future<void> launchSms(String phone, {String text = 'Hi, please call us back.'}) async {
    final cleanPhone = phone.trim();
    if (cleanPhone.isEmpty) return;

    final encodedText = Uri.encodeComponent(text);
    final smsUri = Uri.parse('sms:$cleanPhone?body=$encodedText');
    try {
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(smsUri, mode: LaunchMode.externalNonBrowserApplication);
      }
    } catch (e) {
      debugPrint('SMS launch error: $e');
    }
  }

  Future<void> launchSMS(String phone, {String text = 'Hi, please call us back.'}) => launchSms(phone, text: text);

  // Report Export
  String exportStatus = 'DOWNLOAD XLSX';
  void fakeExport() {
    exportStatus = 'GENERATING...';
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 1200), () {
      exportStatus = '✓ EXPORTED';
      notifyListeners();
      Future.delayed(const Duration(seconds: 2), () {
        exportStatus = 'DOWNLOAD XLSX';
        notifyListeners();
      });
    });
  }

  Future<void> openNativePhoneContactEditor(String phoneNumber, String name) async {
    try {
      await _telephonyChannel.invokeMethod('openSaveContact', {
        'phoneNumber': phoneNumber,
        'name': name,
      });
    } catch (e) {
      debugPrint('openSaveContact error: $e');
    }
  }

  Future<bool> saveContact({required String phoneNumber, required String name, String? notes}) async {
    final success = await ApiService.saveContact(
      phoneNumber: phoneNumber,
      name: name,
      notes: notes,
    );
    if (success) {
      await fetchDeviceCallLogs();
      await fetchBackendData();
      notifyListeners();
    }
    return success;
  }

  Future<Map<String, dynamic>> createUser({
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
    final res = await ApiService.createUser(
      name: name,
      email: email,
      phone: phone,
      password: password,
      role: role,
      team: team,
      dailyTarget: dailyTarget,
      managerId: managerId ?? '',
      managerName: managerName ?? currentUserName,
    );
    if (res['success'] == true) {
      await fetchBackendData();
      notifyListeners();
    }
    return res;
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    super.dispose();
  }
}
