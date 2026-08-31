import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'scheduledTime': scheduledTime.toIso8601String(),
      'note': note,
      'isSnoozed': isSnoozed,
    };
  }

  factory ScheduledCallback.fromMap(Map<String, dynamic> map) {
    return ScheduledCallback(
      id: map['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: map['name']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      scheduledTime: DateTime.tryParse(map['scheduledTime']?.toString() ?? '') ?? DateTime.now(),
      note: map['note']?.toString() ?? '',
      isSnoozed: map['isSnoozed'] == true,
    );
  }
}

class TeleProvider extends ChangeNotifier {
  static const MethodChannel _telephonyChannel = MethodChannel('com.askeva.telesales/telephony');

  UserRole _currentRole = UserRole.caller;
  bool _isLoggedIn = false;
  bool _setupCompleted = false;
  int _activeTabIndex = 1;
  DateTime? _loginSessionTimestamp;
  final Completer<void> _initCompleter = Completer<void>();

  // Real Dynamic SIM Detection
  List<SimCardInfo> _detectedSims = [];
  SimTrackingMode _simTrackingMode = SimTrackingMode.bothSims;
  String _verifiedTrackingNumber = '';
  String _callerName = '';

  UserRole get currentRole => _currentRole;
  bool get isLoggedIn => _isLoggedIn;
  bool get setupCompleted => _setupCompleted;
  Future<void> get initializationDone => _initCompleter.future;
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
  String _currentUserRole = 'caller';
  String get currentUserRole => _currentUserRole;
  String _currentUserTeam = 'Telesales Team';
  String get currentUserTeam => _currentUserTeam;
  String _currentUserId = '';
  String get currentUserId => _currentUserId;
  String _profilePhotoBase64 = '';
  String get profilePhotoBase64 => _profilePhotoBase64;
  String _profilePhotoPath = '';
  String get profilePhotoPath => _profilePhotoPath;

  void setActiveTabIndex(int index) => setTabIndex(index);

  Future<void> _loadPreferencesAndState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isLoggedIn = prefs.getBool('is_logged_in') ?? false;
      _setupCompleted = prefs.getBool('setup_completed') ?? false;
      _authToken = prefs.getString('auth_token') ?? '';
      _verifiedTrackingNumber = prefs.getString('verified_tracking_number') ?? '';
      _callerName = prefs.getString('caller_name') ?? '';
      _autoRecordEnabled = prefs.getBool('auto_record_enabled') ?? true;
      _currentUserRole = prefs.getString('current_user_role') ?? 'caller';
      _currentUserTeam = prefs.getString('current_user_team') ?? 'Telesales Team';
      _currentUserId = prefs.getString('current_user_id') ?? '';
      _profilePhotoBase64 = prefs.getString('profile_photo_base64') ?? '';
      _profilePhotoPath = prefs.getString('profile_photo_path') ?? '';
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
      final savedCbJson = prefs.getString('saved_callbacks_json');
      if (savedCbJson != null && savedCbJson.isNotEmpty) {
        try {
          final List<dynamic> list = jsonDecode(savedCbJson);
          _callbacks.clear();
          for (var item in list) {
            if (item is Map) {
              _callbacks.add(ScheduledCallback.fromMap(Map<String, dynamic>.from(item)));
            }
          }
        } catch (_) {}
      }
      final statusMapJson = prefs.getString('lead_status_overrides_json');
      if (statusMapJson != null && statusMapJson.isNotEmpty) {
        try {
          final Map<String, dynamic> decoded = jsonDecode(statusMapJson);
          _leadStatusOverrides.clear();
          decoded.forEach((k, v) => _leadStatusOverrides[k] = v.toString());
        } catch (_) {}
      }
      final notesMapJson = prefs.getString('lead_notes_json');
      if (notesMapJson != null && notesMapJson.isNotEmpty) {
        try {
          final Map<String, dynamic> decoded = jsonDecode(notesMapJson);
          _leadNotes.clear();
          decoded.forEach((k, v) => _leadNotes[k] = v.toString());
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Error loading saved preferences: $e');
    } finally {
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
      notifyListeners();
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
      await prefs.setString('auth_token', _authToken);
      await prefs.setString('verified_tracking_number', _verifiedTrackingNumber);
      await prefs.setString('caller_name', _callerName);
      await prefs.setBool('auto_record_enabled', _autoRecordEnabled);
      await prefs.setString('sim_tracking_mode', _simTrackingMode.name);
      await prefs.setString('user_role', _currentRole.name);
      await prefs.setString('current_user_role', _currentUserRole);
      await prefs.setString('current_user_team', _currentUserTeam);
      await prefs.setString('current_user_id', _currentUserId);
      await prefs.setString('profile_photo_base64', _profilePhotoBase64);
      await prefs.setString('profile_photo_path', _profilePhotoPath);
      if (_loginSessionTimestamp != null) {
        // Only set initial_setup_timestamp_ms if not already set, preserving 1st login start!
        if (prefs.getInt('initial_setup_timestamp_ms') == null) {
          await prefs.setInt('initial_setup_timestamp_ms', _loginSessionTimestamp!.millisecondsSinceEpoch);
        }
        await prefs.setInt('login_session_timestamp_ms', _loginSessionTimestamp!.millisecondsSinceEpoch);
      }
      if (_callbacks.isNotEmpty) {
        final cbJson = jsonEncode(_callbacks.map((c) => c.toMap()).toList());
        await prefs.setString('saved_callbacks_json', cbJson);
      }
      if (_leadStatusOverrides.isNotEmpty) {
        await prefs.setString('lead_status_overrides_json', jsonEncode(_leadStatusOverrides));
      }
      if (_leadNotes.isNotEmpty) {
        await prefs.setString('lead_notes_json', jsonEncode(_leadNotes));
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

  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> get allUsers => _allUsers;
  String _selectedUserFilter = 'ALL';
  String get selectedUserFilter => _selectedUserFilter;

  List<String> get availableUsersForSelectedTeam {
    final list = <String>['ALL'];
    for (var u in _allUsers) {
      final t = u['team']?.toString() ?? '';
      final name = u['name']?.toString() ?? '';
      if (name.isNotEmpty) {
        if (_selectedTeamFilter == 'ALL' || t.toLowerCase() == _selectedTeamFilter.toLowerCase()) {
          if (!list.contains(name)) list.add(name);
        }
      }
    }
    return list;
  }
  List<String> get userFilterOptions => availableUsersForSelectedTeam;

  int _selectedTimeFilter = 0; // 0 = TODAY, 1 = WEEK, 2 = MONTH
  int get selectedTimeFilter => _selectedTimeFilter;
  DateTime? _selectedCustomDate;
  DateTime? get selectedCustomDate => _selectedCustomDate;
  DateTimeRange? _selectedDateRange;
  DateTimeRange? get selectedDateRange => _selectedDateRange;

  void setTimeFilter(int filter) {
    _selectedTimeFilter = filter;
    _selectedCustomDate = null;
    _selectedDateRange = null;
    notifyListeners();
    fetchBackendData();
  }

  void setCustomDate(DateTime? date) {
    _selectedCustomDate = date;
    _selectedDateRange = null;
    notifyListeners();
    fetchBackendData();
  }

  void setDateRange(DateTimeRange? range) {
    _selectedDateRange = range;
    _selectedCustomDate = null;
    notifyListeners();
    fetchBackendData();
  }

  void setUserFilter(String user) {
    _selectedUserFilter = user;
    notifyListeners();
    fetchBackendData();
  }

  void setTeamFilter(String team) {
    _selectedTeamFilter = team;
    _selectedUserFilter = 'ALL';
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
        if (_selectedUserFilter != 'ALL') {
          nameParam = _selectedUserFilter;
        }
      }

      String? dateParam;
      String? periodParam;
      String? startDateParam;
      String? endDateParam;
      if (_selectedDateRange != null) {
        startDateParam = '${_selectedDateRange!.start.year}-${_selectedDateRange!.start.month.toString().padLeft(2, '0')}-${_selectedDateRange!.start.day.toString().padLeft(2, '0')}';
        endDateParam = '${_selectedDateRange!.end.year}-${_selectedDateRange!.end.month.toString().padLeft(2, '0')}-${_selectedDateRange!.end.day.toString().padLeft(2, '0')}';
      } else if (_selectedCustomDate != null) {
        dateParam = '${_selectedCustomDate!.year}-${_selectedCustomDate!.month.toString().padLeft(2, '0')}-${_selectedCustomDate!.day.toString().padLeft(2, '0')}';
      } else {
        if (_selectedTimeFilter == 0) periodParam = 'today';
        if (_selectedTimeFilter == 1) periodParam = 'week';
        if (_selectedTimeFilter == 2) periodParam = 'month';
      }

      final stats = await ApiService.fetchDashboardStats(
        callerPhone: phoneParam,
        callerName: nameParam,
        team: teamParam,
        userId: nameParam,
        period: periodParam,
        date: dateParam,
        startDate: startDateParam,
        endDate: endDateParam,
        timeFilter: _selectedTimeFilter.toString(),
        loggedInRole: _currentUserRole,
        loggedInTeam: _currentUserTeam,
        loggedInUserId: _currentUserId,
      );
      if (stats != null) {
        _backendStats = stats;
        if (stats['teams'] != null) {
          final rawTeams = List<String>.from((stats['teams'] as List).map((t) => t.toString()));
          final filtered = rawTeams.where((t) =>
            t != 'ALL' &&
            t != 'ALL TEAMS' &&
            t != 'BD TEAM - AE' &&
            t != 'BDE' &&
            t != 'Telesales Mumbai'
          ).toList();
          _availableTeams = ['ALL', ...(filtered.isNotEmpty ? filtered : ['Telesales Team', 'Management'])];
        }
        if (stats['allUsers'] != null) {
          _allUsers = List<Map<String, dynamic>>.from((stats['allUsers'] as List).map((u) => Map<String, dynamic>.from(u)));
        }
      }
      final emps = await ApiService.fetchLeaderboard(
        callerPhone: phoneParam,
        callerName: nameParam,
        team: teamParam,
        userId: nameParam,
        period: periodParam,
        date: dateParam,
        startDate: startDateParam,
        endDate: endDateParam,
        timeFilter: _selectedTimeFilter.toString(),
        loggedInRole: _currentUserRole,
        loggedInTeam: _currentUserTeam,
        loggedInUserId: _currentUserId,
      );
      _teamEmployees = emps ?? [];

      final recs = await ApiService.fetchRecordings(
        callerPhone: phoneParam,
        callerName: nameParam,
        team: teamParam,
        userId: nameParam,
        loggedInRole: _currentUserRole,
        loggedInTeam: _currentUserTeam,
        loggedInUserId: _currentUserId,
      );
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

      final backendLeads = await ApiService.fetchLeads(
        callerPhone: phoneParam,
        callerName: nameParam,
        team: teamParam,
        userId: nameParam,
        loggedInRole: _currentUserRole,
        loggedInTeam: _currentUserTeam,
        loggedInUserId: _currentUserId,
      );
      if (backendLeads != null) {
        for (var bl in backendLeads) {
          final cleanP = bl.phone.replaceAll(RegExp(r'[^0-9]'), '');
          final last10 = cleanP.length >= 10 ? cleanP.substring(cleanP.length - 10) : cleanP;

          // Apply saved local status override if present
          if (_leadStatusOverrides.containsKey(bl.phone)) {
            final st = _leadStatusOverrides[bl.phone]!;
            bl.status = LeadStatus.values.firstWhere((e) => e.name == st, orElse: () => bl.status);
          }
          if (_leadNotes.containsKey(bl.phone)) {
            bl.note = _leadNotes[bl.phone]!;
          }

          final existingIdx = _leads.indexWhere((l) =>
              l.id == bl.id ||
              l.phone == bl.phone ||
              (last10.isNotEmpty && l.phone.replaceAll(RegExp(r'[^0-9]'), '').endsWith(last10)));

          if (existingIdx != -1) {
            _leads[existingIdx] = bl;
          } else {
            _leads.add(bl);
          }
        }
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

            final sessionMs = _loginSessionTimestamp?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
            if (timestampMs < sessionMs - 5000) {
              continue; // Only track and sync calls made during the active user work session
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

  Future<bool> pickAndSaveProfilePhoto({ImageSource source = ImageSource.gallery}) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 80,
      );

      if (picked != null) {
        final bytes = await picked.readAsBytes();
        _profilePhotoBase64 = base64Encode(bytes);
        _profilePhotoPath = picked.path;
        await _savePreferences();

        if (_currentUserId.isNotEmpty) {
          await ApiService.uploadProfilePhoto(
            userId: _currentUserId,
            photoBase64: _profilePhotoBase64,
          );
        }

        await fetchBackendData();
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('TeleProvider.pickAndSaveProfilePhoto error: $e');
    }
    return false;
  }

  Future<void> clearProfilePhoto() async {
    _profilePhotoBase64 = '';
    _profilePhotoPath = '';
    await _savePreferences();
    if (_currentUserId.isNotEmpty) {
      await ApiService.uploadProfilePhoto(
        userId: _currentUserId,
        photoBase64: '',
      );
    }
    notifyListeners();
  }

  void purgeUserSession() {
    _isLoggedIn = false;
    _setupCompleted = true; // Permanently preserve setup completion so onboarding/permissions are never shown again!
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
          final userRole = (user?['role']?.toString() ?? 'manager').toLowerCase();
          if (userRole == 'caller') {
            return {
              'success': false,
              'message': 'This account is registered as a Caller Agent. Please switch to the Caller tab to log in.'
            };
          }
          if (user != null) {
            if (user['name'] != null) _callerName = user['name'].toString();
            if (user['email'] != null) _verifiedTrackingNumber = user['email'].toString();
            _currentUserRole = userRole;
            _currentUserTeam = user['team']?.toString() ?? 'Management';
            _currentUserId = user['id']?.toString() ?? '';
          }
          _currentRole = UserRole.manager;
          _isLoggedIn = true;
          _setupCompleted = true;

          final prefs = await SharedPreferences.getInstance();
          final initMs = prefs.getInt('initial_setup_timestamp_ms');
          if (initMs != null) {
            _loginSessionTimestamp = DateTime.fromMillisecondsSinceEpoch(initMs);
          } else {
            _loginSessionTimestamp ??= DateTime.now();
          }

          _savePreferences();
          await fetchBackendData();
          notifyListeners();
          return {'success': true, 'message': 'Manager authentication successful'};
        }
        return {'success': false, 'message': res?['message']?.toString() ?? 'Account not registered in DB or incorrect password.'};
      } else {
        final res = await ApiService.verifyCaller(username, password: password);
        if (res != null && res['success'] == true) {
          final user = res['user'] as Map<String, dynamic>?;
          final userRole = (user?['role']?.toString() ?? 'caller').toLowerCase();
          if (userRole == 'manager' || userRole == 'admin') {
            return {
              'success': false,
              'message': 'This account is registered as a Manager. Please switch to the Manager tab to log in.'
            };
          }

          String regPhone = '';
          if (user != null) {
            if (user['name'] != null) _callerName = user['name'].toString();
            if (user['phone'] != null && user['phone'].toString().isNotEmpty) {
              _verifiedTrackingNumber = user['phone'].toString();
              regPhone = user['phone'].toString();
            }
            _currentUserRole = userRole;
            _currentUserTeam = user['team']?.toString() ?? 'Telesales Team';
            _currentUserId = user['id']?.toString() ?? '';
          }

          // If logged in via Email ID with no registered phone in DB, ask for mobile number verification
          if (regPhone.isEmpty) {
            return {
              'success': false,
              'requiresPhoneInput': true,
              'user': user,
              'message': 'Please verify your SIM card tracking phone number to complete setup.'
            };
          }

          _currentRole = UserRole.caller;
          _isLoggedIn = true;
          _setupCompleted = true;

          final prefs = await SharedPreferences.getInstance();
          final initMs = prefs.getInt('initial_setup_timestamp_ms');
          if (initMs != null) {
            _loginSessionTimestamp = DateTime.fromMillisecondsSinceEpoch(initMs);
          } else {
            _loginSessionTimestamp ??= DateTime.now();
          }

          _savePreferences();
          await fetchDeviceCallLogs();
          await fetchBackendData();
          notifyListeners();
          return {'success': true, 'message': 'Caller authentication successful'};
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

  // Filtered by active SIM Slot & Time Period (Today / Week / Month / Custom Date / Date Range)
  List<CallLogModel> get simTrackedCallLogs {
    List<CallLogModel> list;
    switch (_simTrackingMode) {
      case SimTrackingMode.sim1Only:
        list = _callLogs.where((c) => c.simSlot == 1).toList();
        break;
      case SimTrackingMode.sim2Only:
        list = _callLogs.where((c) => c.simSlot == 2).toList();
        break;
      case SimTrackingMode.bothSims:
        list = _callLogs;
        break;
    }

    if (_selectedDateRange != null) {
      final start = DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day, 0, 0, 0);
      final end = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day, 23, 59, 59, 999);
      return list.where((c) => c.timestamp.isAfter(start.subtract(const Duration(milliseconds: 1))) && c.timestamp.isBefore(end.add(const Duration(milliseconds: 1)))).toList();
    }

    if (_selectedCustomDate != null) {
      return list.where((c) =>
        c.timestamp.year == _selectedCustomDate!.year &&
        c.timestamp.month == _selectedCustomDate!.month &&
        c.timestamp.day == _selectedCustomDate!.day
      ).toList();
    }

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    if (_selectedTimeFilter == 0) {
      // TODAY
      return list.where((c) => c.timestamp.isAfter(todayStart.subtract(const Duration(milliseconds: 1))) && c.timestamp.isBefore(todayEnd.add(const Duration(milliseconds: 1)))).toList();
    } else if (_selectedTimeFilter == 1) {
      // THIS WEEK (Monday to today)
      final dayOfWeek = now.weekday; // 1 = Monday, 7 = Sunday
      final weekStart = DateTime(now.year, now.month, now.day - (dayOfWeek - 1));
      return list.where((c) => c.timestamp.isAfter(weekStart.subtract(const Duration(milliseconds: 1))) && c.timestamp.isBefore(todayEnd.add(const Duration(milliseconds: 1)))).toList();
    } else if (_selectedTimeFilter == 2) {
      // THIS MONTH (1st of current month to today)
      final monthStart = DateTime(now.year, now.month, 1);
      return list.where((c) => c.timestamp.isAfter(monthStart.subtract(const Duration(milliseconds: 1))) && c.timestamp.isBefore(todayEnd.add(const Duration(milliseconds: 1)))).toList();
    }

    return list;
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

  // Telemetry Aggregates & Accurate Average Calculations
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

  Duration get trackedAverageTalkTime {
    final connected = trackedConnectedCalls;
    if (connected == 0) return Duration.zero;
    final avgSeconds = trackedTotalTalkTime.inSeconds ~/ connected;
    return Duration(seconds: avgSeconds);
  }

  String get trackedAverageTalkTimeFormatted {
    final d = trackedAverageTalkTime;
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  double get trackedConnectRate {
    if (trackedTotalCalls == 0) return 0.0;
    return (trackedConnectedCalls / trackedTotalCalls) * 100;
  }

  // Phone Number Verification & Duplicate Detection
  bool isPhoneNumberValid(String phone) {
    final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return clean.length >= 10;
  }

  bool isDuplicateLeadPhone(String phone, {String? excludeLeadId}) {
    final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length < 6) return false;
    final last10 = clean.length >= 10 ? clean.substring(clean.length - 10) : clean;
    return _leads.any((l) {
      if (excludeLeadId != null && l.id == excludeLeadId) return false;
      final lClean = l.phone.replaceAll(RegExp(r'[^0-9]'), '');
      final lLast10 = lClean.length >= 10 ? lClean.substring(lClean.length - 10) : lClean;
      return last10 == lLast10;
    });
  }

  // Real Dynamic Leads derived from actual phone contacts, call logs & MongoDB backend
  final List<LeadModel> _leads = [];
  List<LeadModel> get leads => _leads;
  final Map<String, String> _leadStatusOverrides = {};
  final Map<String, String> _leadNotes = {};

  void _syncLeadsFromCallLogs() {
    final Map<String, LeadModel> uniqueClients = {};

    // 1. First keep existing leads in memory
    for (var l in _leads) {
      if (l.phone.isNotEmpty) {
        uniqueClients[l.phone] = l;
      }
    }

    // 2. Merge call logs without overriding user-set statuses
    for (var call in _callLogs) {
      if (call.phoneNumber.isNotEmpty) {
        final phone = call.phoneNumber;
        if (!uniqueClients.containsKey(phone)) {
          LeadStatus status = LeadStatus.other;
          if (_leadStatusOverrides.containsKey(phone)) {
            final stName = _leadStatusOverrides[phone]!;
            status = LeadStatus.values.firstWhere((e) => e.name == stName, orElse: () => LeadStatus.other);
          } else if (call.duration.inMinutes >= 5) {
            status = LeadStatus.won;
          } else if (call.duration.inSeconds > 60) {
            status = LeadStatus.interested;
          } else if (call.type == CallType.missed || call.type == CallType.rejected) {
            status = LeadStatus.followUp;
          }

          final note = _leadNotes[phone] ?? call.note ?? (status == LeadStatus.won ? 'Order inquiry' : 'Recent phone dial');

          uniqueClients[phone] = LeadModel(
            id: call.id,
            name: call.contactName,
            phone: phone,
            status: status,
            attempts: 1,
            dateAdded: call.timestamp,
            lastCallDate: call.timestamp,
            note: note,
          );
        } else {
          final existing = uniqueClients[phone]!;
          if (call.contactName != 'Unknown' && call.contactName.isNotEmpty && (existing.name == 'Unknown' || existing.name.isEmpty)) {
            existing.name = call.contactName;
          }
          if (_leadStatusOverrides.containsKey(phone)) {
            final stName = _leadStatusOverrides[phone]!;
            existing.status = LeadStatus.values.firstWhere((e) => e.name == stName, orElse: () => existing.status);
          }
          if (_leadNotes.containsKey(phone)) {
            existing.note = _leadNotes[phone]!;
          }
        }
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

  Future<void> updateLeadStatus(
    String leadIdOrPhone,
    LeadStatus newStatus, {
    String? phone,
    String? name,
    String? note,
  }) async {
    final cleanPhone = (phone ?? leadIdOrPhone).replaceAll(RegExp(r'[^0-9]'), '');
    final last10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;

    LeadModel? targetLead;
    int idx = _leads.indexWhere((l) =>
        l.id == leadIdOrPhone ||
        l.phone == leadIdOrPhone ||
        (last10.isNotEmpty && l.phone.replaceAll(RegExp(r'[^0-9]'), '').endsWith(last10)));

    if (idx != -1) {
      targetLead = _leads[idx];
      targetLead.status = newStatus;
      if (name != null && name.isNotEmpty) targetLead.name = name;
      if (note != null && note.isNotEmpty) targetLead.note = note;
    } else {
      // Create new lead if it wasn't present
      targetLead = LeadModel(
        id: leadIdOrPhone,
        name: name ?? 'Lead Client',
        phone: phone ?? leadIdOrPhone,
        status: newStatus,
        attempts: 1,
        dateAdded: DateTime.now(),
        lastCallDate: DateTime.now(),
        note: note ?? '',
      );
      _leads.insert(0, targetLead);
    }

    final finalPhone = targetLead.phone;
    if (finalPhone.isNotEmpty) {
      _leadStatusOverrides[finalPhone] = newStatus.name;
      if (note != null && note.isNotEmpty) {
        _leadNotes[finalPhone] = note;
      }
    }

    if (newStatus == LeadStatus.followUp) {
      if (!_callbacks.any((c) => c.phone == finalPhone)) {
        _callbacks.insert(
          0,
          ScheduledCallback(
            id: 'lead_cb_${targetLead.id}',
            name: targetLead.name.isNotEmpty && targetLead.name != 'Unknown' ? targetLead.name : targetLead.phone,
            phone: targetLead.phone,
            scheduledTime: DateTime.now().add(const Duration(hours: 4)),
            note: 'Lead moved to Follow-up status',
          ),
        );
      }
    }

    _savePreferences();
    notifyListeners();

    // Persist to MongoDB backend CRM database
    try {
      await ApiService.updateLeadStatus(
        leadId: targetLead.id,
        status: newStatus.name,
        phone: targetLead.phone,
        name: targetLead.name,
        note: targetLead.note,
        callerName: _callerName,
      );
    } catch (e) {
      debugPrint('updateLeadStatus backend sync notice: $e');
    }
  }

  Future<void> addLeadNote(String leadIdOrPhone, String newNote) async {
    final cleanPhone = leadIdOrPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final last10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;

    final idx = _leads.indexWhere((l) =>
        l.id == leadIdOrPhone ||
        l.phone == leadIdOrPhone ||
        (last10.isNotEmpty && l.phone.replaceAll(RegExp(r'[^0-9]'), '').endsWith(last10)));

    if (idx != -1) {
      final lead = _leads[idx];
      lead.note = newNote;
      if (lead.phone.isNotEmpty) {
        _leadNotes[lead.phone] = newNote;
      }
      _savePreferences();
      notifyListeners();

      try {
        await ApiService.updateLeadStatus(
          leadId: lead.id,
          status: lead.status.name,
          phone: lead.phone,
          name: lead.name,
          note: newNote,
          callerName: _callerName,
        );
      } catch (e) {
        debugPrint('addLeadNote backend sync notice: $e');
      }
    }
  }

  // Scheduled Callbacks (100% Dynamic - strictly for current session & user-scheduled)
  final List<ScheduledCallback> _callbacks = [];

  List<ScheduledCallback> get callbacks => _callbacks;

  void _syncCallbacksFromCallLogs() {
    final Set<String> existingPhones = _callbacks.map((c) => c.phone).toSet();
    // Only capture missed calls that happen during the active telesales session
    final sessionStart = _loginSessionTimestamp;
    if (sessionStart == null) return;

    for (var call in _callLogs) {
      if (call.timestamp.isAfter(sessionStart) &&
          (call.type == CallType.missed || call.type == CallType.rejected) &&
          call.phoneNumber.isNotEmpty &&
          !existingPhones.contains(call.phoneNumber)) {
        _callbacks.add(
          ScheduledCallback(
            id: 'cb_${call.id}',
            name: call.contactName != 'Unknown' ? call.contactName : call.phoneNumber,
            phone: call.phoneNumber,
            scheduledTime: DateTime.now().add(const Duration(hours: 2)),
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

  Future<bool> deleteRecording(String id) async {
    _recordings.removeWhere((r) => r.id == id);
    notifyListeners();
    try {
      final res = await ApiService.deleteRecording(id);
      return res;
    } catch (e) {
      debugPrint('deleteRecording error: $e');
      return false;
    }
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
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final last10 = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;
    final idx = _leads.indexWhere((l) =>
        l.phone == phoneNumber ||
        (last10.isNotEmpty && l.phone.replaceAll(RegExp(r'[^0-9]'), '').endsWith(last10)));
    if (idx != -1) {
      _leads[idx].name = name;
      if (notes != null && notes.isNotEmpty) _leads[idx].note = notes;
    }
    if (notes != null && notes.isNotEmpty) {
      _leadNotes[phoneNumber] = notes;
    }
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

  // ================= DUTY & BREAK TRACKING =================
  bool _isOnDuty = true;
  bool get isOnDuty => _isOnDuty;
  DateTime _dutyStartTime = DateTime.now().subtract(const Duration(hours: 5, minutes: 6));
  DateTime get dutyStartTime => _dutyStartTime;

  bool _isOnBreak = false;
  bool get isOnBreak => _isOnBreak;
  String _currentBreakType = '';
  String get currentBreakType => _currentBreakType;
  DateTime? _breakStartTime;

  final List<Map<String, dynamic>> _breakLogs = [
    {
      'type': 'Tea break',
      'start': '11:15',
      'end': '11:25',
      'dur': '10M',
      'mins': 10,
    },
    {
      'type': 'Lunch',
      'start': '1:05',
      'end': '1:19',
      'dur': '14M',
      'mins': 14,
    },
  ];
  List<Map<String, dynamic>> get breakLogs => _breakLogs;
  int get totalBreakMinutes => _breakLogs.fold(0, (sum, b) => sum + (b['mins'] as int? ?? 0));

  void toggleDuty() {
    _isOnDuty = !_isOnDuty;
    if (_isOnDuty) {
      _dutyStartTime = DateTime.now();
      _isOnBreak = false;
    }
    notifyListeners();
  }

  void startBreak(String type) {
    _isOnBreak = true;
    _currentBreakType = type;
    _breakStartTime = DateTime.now();
    notifyListeners();
  }

  void endBreak() {
    if (_isOnBreak && _breakStartTime != null) {
      final end = DateTime.now();
      final diff = end.difference(_breakStartTime!);
      final mins = diff.inMinutes > 0 ? diff.inMinutes : 1;
      final startH = _breakStartTime!.hour % 12 == 0 ? 12 : _breakStartTime!.hour % 12;
      final startStr = '$startH:${_breakStartTime!.minute.toString().padLeft(2, '0')}';
      final endH = end.hour % 12 == 0 ? 12 : end.hour % 12;
      final endStr = '$endH:${end.minute.toString().padLeft(2, '0')}';
      _breakLogs.insert(0, {
        'type': _currentBreakType.isNotEmpty ? _currentBreakType : 'Break',
        'start': startStr,
        'end': endStr,
        'dur': '${mins}M',
        'mins': mins,
      });
    }
    _isOnBreak = false;
    _currentBreakType = '';
    _breakStartTime = null;
    notifyListeners();
  }

  // ================= CALL SESSION ORCHESTRATION =================
  List<LeadModel> _sessionQueue = [];
  List<LeadModel> get sessionQueue => _sessionQueue;
  int _sessionIndex = 0;
  int get sessionIndex => _sessionIndex;
  LeadModel? _activeCallLead;
  LeadModel? get activeCallLead => _activeCallLead;

  int _callTimerSeconds = 0;
  int get callTimerSeconds => _callTimerSeconds;
  String get callTimerFormatted {
    final m = (_callTimerSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_callTimerSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Timer? _sessionCallTimer;
  bool _isCallMuted = false;
  bool get isCallMuted => _isCallMuted;
  bool _isCallOnHold = false;
  bool get isCallOnHold => _isCallOnHold;
  bool _isKeypadOpen = false;
  bool get isKeypadOpen => _isKeypadOpen;
  String _selectedAudioOutput = 'BT Headset · boAt 331';
  String get selectedAudioOutput => _selectedAudioOutput;

  void toggleMute() {
    _isCallMuted = !_isCallMuted;
    notifyListeners();
  }

  void toggleHold() {
    _isCallOnHold = !_isCallOnHold;
    notifyListeners();
  }

  void toggleKeypad() {
    _isKeypadOpen = !_isKeypadOpen;
    notifyListeners();
  }

  void setAudioOutput(String output) {
    _selectedAudioOutput = output;
    notifyListeners();
  }

  void startCallSession({List<LeadModel>? leads, int startIndex = 0}) {
    final available = leads ?? _leads.where((l) => l.status != LeadStatus.won && l.status != LeadStatus.lost).toList();
    _sessionQueue = available.isNotEmpty ? available : [
      LeadModel(
        id: 'demo_1',
        name: 'Ganesh Enterprises',
        phone: '+91 98400 11223',
        status: LeadStatus.newLead,
        attempts: 0,
        dateAdded: DateTime.now(),
        lastCallDate: DateTime.now(),
        note: 'Fresh IndiaMART inquiry',
      ),
      LeadModel(
        id: 'demo_2',
        name: 'Lakshmi Traders',
        phone: '+91 90940 55667',
        status: LeadStatus.newLead,
        attempts: 0,
        dateAdded: DateTime.now(),
        lastCallDate: DateTime.now(),
        note: 'Wholesale enquiry',
      ),
      LeadModel(
        id: 'demo_3',
        name: 'Meenakshi Agencies',
        phone: '+91 90250 11876',
        status: LeadStatus.followUp,
        attempts: 1,
        dateAdded: DateTime.now(),
        lastCallDate: DateTime.now(),
        note: 'Follow up quote',
      ),
    ];
    _sessionIndex = startIndex.clamp(0, _sessionQueue.length - 1);
    _activeCallLead = _sessionQueue[_sessionIndex];
    _callTimerSeconds = 0;
    _isCallMuted = false;
    _isCallOnHold = false;
    _isKeypadOpen = false;

    _sessionCallTimer?.cancel();
    _sessionCallTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _callTimerSeconds++;
      notifyListeners();
    });

    // Make native direct phone call
    if (_activeCallLead != null) {
      makeDirectCall(_activeCallLead!.phone);
    }
    notifyListeners();
  }

  void endSessionCall() {
    _sessionCallTimer?.cancel();
    _sessionCallTimer = null;
    notifyListeners();
  }

  LeadModel? get nextSessionLead {
    if (_sessionIndex + 1 < _sessionQueue.length) {
      return _sessionQueue[_sessionIndex + 1];
    }
    return null;
  }

  int get remainingSessionCount => (_sessionQueue.length - _sessionIndex - 1).clamp(0, 999);

  Future<void> saveCallOutcomeAndNext({
    required LeadStatus status,
    String? note,
    bool sendBrochure = false,
    DateTime? callbackTime,
    bool takeBreak = false,
  }) async {
    final currentLead = _activeCallLead;
    if (currentLead != null) {
      await updateLeadStatus(
        currentLead.id,
        status,
        phone: currentLead.phone,
        name: currentLead.name,
        note: note,
      );

      if (callbackTime != null) {
        addScheduledCallback(
          name: currentLead.name,
          phone: currentLead.phone,
          scheduledTime: callbackTime,
          note: note ?? 'Follow-up callback',
        );
      }

      if (sendBrochure) {
        launchWhatsApp(
          currentLead.phone,
          text: 'Hello ${currentLead.name}, thank you for your time on call. Here is the ASKEVA product pricing & brochure deck for your review.',
        );
      }
    }

    if (takeBreak) {
      startBreak('Quick Break');
      _activeCallLead = null;
      notifyListeners();
      return;
    }

    // Advance to next lead if available
    if (_sessionIndex + 1 < _sessionQueue.length) {
      _sessionIndex++;
      _activeCallLead = _sessionQueue[_sessionIndex];
      _callTimerSeconds = 0;
      _isCallMuted = false;
      _isCallOnHold = false;
      _isKeypadOpen = false;

      _sessionCallTimer?.cancel();
      _sessionCallTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _callTimerSeconds++;
        notifyListeners();
      });

      makeDirectCall(_activeCallLead!.phone);
    } else {
      _activeCallLead = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sessionCallTimer?.cancel();
    _syncPollingTimer?.cancel();
    _recordingTimer?.cancel();
    super.dispose();
  }
}
