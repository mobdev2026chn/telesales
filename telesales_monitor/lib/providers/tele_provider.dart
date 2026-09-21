import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
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
import '../services/api_parsers.dart';
import '../services/api_service.dart';
import '../services/call_recording_setup.dart';
import '../services/work_sim.dart';

enum UserRole { manager, caller }
enum SimTrackingMode { sim1Only, sim2Only, bothSims }

class ScheduledCallback {
  final String id;
  String name;
  final String phone;
  DateTime scheduledTime;
  String note;
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
    ApiService.onAuthRequired = _handleAuthRequired;
    _initChannelListener();
    _lifecycleListener = AppLifecycleListener(onStateChange: _onAppLifecycleChanged);
    _loadPreferencesAndState();
  }

  /// Called by the app shell to route to the login screen when the session expired server-side.
  VoidCallback? onSessionExpired;

  /// Bumped on every login / logout. Async work captures it and drops its result if it changed,
  /// so a request that finishes after logout can never write the previous user's data back.
  int _sessionGeneration = 0;
  bool _isCurrentSession(int gen) => gen == _sessionGeneration;

  AppLifecycleListener? _lifecycleListener;
  bool _appInForeground = true;

  void _onAppLifecycleChanged(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _appInForeground) return;
    _appInForeground = foreground;
    if (foreground) {
      _startPeriodicSyncTimer();
      if (_isLoggedIn) {
        fetchNotifications();
        // (Re)start call tracking while we are allowed to: after a reboot, an update or a kill
        syncCallMonitor();
        CallRecordingChannel.retryUploads();
        _refreshRecordings();
        // Calls made while the app was in the background, and target changes made by the admin
        refreshProfile();
        _refreshLiveNumbers();
        refreshRecordingSetupStatus();
      }
    } else {
      _syncPollingTimer?.cancel();
      _syncPollingTimer = null;
    }
  }

  bool _handlingAuthExpiry = false;
  Future<void> _handleAuthRequired() async {
    if (_handlingAuthExpiry || !_isLoggedIn) return;
    _handlingAuthExpiry = true;
    try {
      await purgeUserSession();
      onSessionExpired?.call();
    } finally {
      _handlingAuthExpiry = false;
    }
  }

  bool _autoRecordEnabled = true;
  bool get autoRecordEnabled => _autoRecordEnabled;

  bool _isCallRecordingActive = false;
  bool get isCallRecordingActive => _isCallRecordingActive;

  void toggleAutoRecord() {
    _autoRecordEnabled = !_autoRecordEnabled;
    _pushAutoRecordToNative();
    _savePreferences();
    notifyListeners();
  }

  /// Recording is only armed for a signed-in caller (or a manager in caller mode) with
  /// auto-record on: the native call monitor runs exactly then.
  void _pushAutoRecordToNative() {
    syncCallMonitor();
  }

  /// True when the app is acting as a caller: a caller login, or a manager who switched to caller mode.
  bool get _isCallerContext => _currentRole == UserRole.caller || _isManagerCallerMode;

  Timer? _callLogDebounce;

  void _initChannelListener() {
    _telephonyChannel.setMethodCallHandler((call) async {
      if (call.method == 'onCallRecordingStatus') {
        final active = (call.arguments is Map) ? call.arguments['isRecording'] == true : false;
        if (active != _isCallRecordingActive) {
          _isCallRecordingActive = active;
          notifyListeners();
        }
      } else if (call.method == 'onCallStateChanged') {
        // The call-log observer fires several times per call: coalesce into one refresh + sync.
        _callLogDebounce?.cancel();
        _callLogDebounce = Timer(const Duration(seconds: 2), () {
          fetchDeviceCallLogs();
        });
      } else if (call.method == 'onCallsPushed') {
        // The call monitor sent the latest calls to the server: show the server's new numbers
        if (_isLoggedIn) await _refreshServerStats();
      } else if (call.method == 'onRecordingUploaded') {
        // The native queue uploaded recordings: show them
        await refreshPendingUploadCount();
        await _refreshRecordings();
      } else if (call.method == 'onUploadQueueChanged') {
        // Also sent when a call has been processed: the last capture result may have changed
        await refreshPendingUploadCount();
        await refreshRecordingSetupStatus();
      } else if (call.method == 'onUploadAuthFailed') {
        // The server rejected the token: /auth/me confirms it and signs out (onAuthRequired)
        await refreshProfile();
      } else if (call.method == 'onCallMonitorState') {
        final running = (call.arguments is Map) && call.arguments['running'] == true;
        if (running != _callMonitorRunning) {
          _callMonitorRunning = running;
          notifyListeners();
        }
      } else if (call.method == 'onPlaybackCompleted') {
        _onPlaybackFinished();
      }
    });
  }

  // ================= CALL MONITOR & RECORDING UPLOADS =================
  // Recording, built-in recorder detection and uploads are native (CallMonitorService +
  // RecordingUploader): they keep working when this engine is gone. Dart starts / stops the
  // service and refreshes the recordings list when native reports finished uploads.

  int _pendingUploadCount = 0;
  int get pendingUploadCount => _pendingUploadCount;

  bool _callMonitorRunning = false;
  bool get callMonitorRunning => _callMonitorRunning;

  bool get _shouldRunCallMonitor => shouldRunCallMonitor(
        isLoggedIn: _isLoggedIn,
        isCallerContext: _isCallerContext,
        autoRecordEnabled: _autoRecordEnabled,
        authToken: _authToken,
      );

  /// Starts the call monitor for a signed-in caller (only while in the foreground: Android does
  /// not allow starting a microphone service from the background), or stops it.
  Future<void> syncCallMonitor() async {
    if (!_shouldRunCallMonitor) {
      if (_callMonitorRunning) {
        _callMonitorRunning = false;
        notifyListeners();
      }
      await CallRecordingChannel.stopMonitor();
      return;
    }
    if (!_appInForeground) return;
    // Preferences first: the native side reads the session (token, user, SIM mode) from them
    await _savePreferences();
    final started = await CallRecordingChannel.startMonitor(baseUrl: ApiService.baseUrl);
    if (started != _callMonitorRunning) {
      _callMonitorRunning = started;
      notifyListeners();
    }
    await refreshPendingUploadCount();
  }

  Future<void> refreshPendingUploadCount() async {
    if (!_isLoggedIn || _currentUserId.isEmpty) {
      _pendingUploadCount = 0;
      return;
    }
    final n = await CallRecordingChannel.pendingUploadCount(_currentUserId);
    if (n != _pendingUploadCount) {
      _pendingUploadCount = n;
      notifyListeners();
    }
  }

  /// Recordings the previous (Dart) uploader had queued move to the native queue once.
  Future<void> _migrateLegacyPendingUploads(SharedPreferences prefs) async {
    final json = prefs.getString('pending_recording_uploads');
    if (json == null || json.isEmpty) return;
    try {
      final list = jsonDecode(json);
      final items = list is List ? legacyUploadsForNative(list) : const <Map<String, dynamic>>[];
      final added = await CallRecordingChannel.enqueueLegacyUploads(items);
      if (added < 0) return; // channel unavailable: keep them for the next start
    } catch (e) {
      debugPrint('Legacy upload migration: $e');
    }
    await prefs.remove('pending_recording_uploads');
  }

  /// Only calls on the registered (work) SIM are tracked and sent to the server.
  /// SIM slot 0 means the device could not tell which SIM carried the call: kept when both SIMs are
  /// tracked or the phone has one SIM; on a dual-SIM phone it may be the personal SIM, so it is dropped
  /// (same rule as CallMonitorStore.isWorkSim on the native side).
  bool _isWorkSim(int simSlot) => isWorkSimCall(simSlot, _simTrackingMode.name, _detectedSims.length);

  String _authToken = '';
  String get authToken => _authToken;
  String _currentUserRole = 'caller';
  String get currentUserRole => _currentUserRole;
  String _currentUserTeam = 'Telesales Team';
  String get currentUserTeam => _currentUserTeam;
  String _currentUserId = '';
  String get currentUserId => _currentUserId;
  int _currentUserDailyTarget = kDefaultDailyTarget;
  /// Per-user daily call target set by the admin (falls back to the default).
  int get dailyTarget => _currentUserDailyTarget > 0 ? _currentUserDailyTarget : kDefaultDailyTarget;
  String _profilePhotoBase64 = '';
  String get profilePhotoBase64 => _profilePhotoBase64;
  String _profilePhotoPath = '';
  String get profilePhotoPath => _profilePhotoPath;

  void setActiveTabIndex(int index) => setTabIndex(index);

  final Map<String, String> _crmContactNames = {};
  Map<String, String> get crmContactNames => _crmContactNames;
  final Set<String> _readNotificationIds = {};

  int _activeSimSlot = 1;
  int get activeSimSlot => _activeSimSlot;

  void setActiveSimSlot(int slot) {
    _activeSimSlot = slot;
    _simTrackingMode = (slot == 1)
        ? SimTrackingMode.sim1Only
        : (slot == 2 ? SimTrackingMode.sim2Only : SimTrackingMode.bothSims);
    _savePreferences();
    notifyListeners();
  }

  String _currentUserEmail = '';
  String get currentUserEmail => _currentUserEmail;

  bool _isManagerCallerMode = false;
  bool get isManagerCallerMode => _isManagerCallerMode;

  void toggleManagerCallerMode() {
    _isManagerCallerMode = !_isManagerCallerMode;
    _backendStats = null; // team numbers must never be shown as the manager's personal numbers
    _todayStats = null;
    _pushAutoRecordToNative();
    _savePreferences();
    notifyListeners();
    if (_isManagerCallerMode) {
      fetchDeviceCallLogs();
    } else {
      _callLogs.clear();
      _allDeviceCalls.clear();
    }
    fetchBackendData();
  }

  int _callQualityFilter = 0; // 0 = ALL, 1 = SHORT (<2M), 2 = MEDIUM (2-5M), 3 = LONG (>5M), 4 = UNANSWERED
  int get callQualityFilter => _callQualityFilter;

  void setCallQualityFilter(int filter) {
    _callQualityFilter = filter;
    notifyListeners();
  }

  Future<void> _loadPreferencesAndState() async {
    var mustReauthenticate = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      _isLoggedIn = prefs.getBool('is_logged_in') ?? false;
      _setupCompleted = prefs.getBool('setup_completed') ?? false;
      _authToken = prefs.getString('auth_token') ?? '';
      ApiService.setToken(_authToken);
      // Sessions from older builds carry no real JWT: the server rejects them, so sign in again.
      if (_isLoggedIn && (_authToken.isEmpty || _authToken.startsWith('jwt_'))) {
        mustReauthenticate = true;
      }
      _verifiedTrackingNumber = prefs.getString('verified_tracking_number') ?? '';
      _callerName = prefs.getString('caller_name') ?? '';
      _autoRecordEnabled = prefs.getBool('auto_record_enabled') ?? true;
      _currentUserRole = prefs.getString('current_user_role') ?? 'caller';
      _currentUserTeam = prefs.getString('current_user_team') ?? 'Telesales Team';
      _currentUserId = prefs.getString('current_user_id') ?? '';
      _currentUserEmail = prefs.getString('current_user_email') ?? '';
      _currentUserDailyTarget = prefs.getInt('current_user_daily_target') ?? kDefaultDailyTarget;
      _isManagerCallerMode = prefs.getBool('manager_caller_mode') ?? false;
      _profilePhotoBase64 = prefs.getString('profile_photo_base64') ?? '';
      _profilePhotoPath = prefs.getString('profile_photo_path') ?? '';
      _isOnDuty = prefs.getBool('is_on_duty') ?? false;
      final dutyMs = prefs.getInt('duty_start_ms');
      _dutyStartTime = dutyMs != null ? DateTime.fromMillisecondsSinceEpoch(dutyMs) : null;
      final syncAckMs = prefs.getInt(_syncAckKey(_currentUserId));
      _lastCallSyncAck = syncAckMs != null ? DateTime.fromMillisecondsSinceEpoch(syncAckMs) : null;
      await _migrateLegacyPendingUploads(prefs);
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
      if (_isLoggedIn) {
        final sessionMs = prefs.getInt('login_session_timestamp_ms');
        if (sessionMs != null) {
          _loginSessionTimestamp = DateTime.fromMillisecondsSinceEpoch(sessionMs);
        } else {
          _loginSessionTimestamp = DateTime.now();
        }
      } else {
        _loginSessionTimestamp = null;
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
      final savedReadIds = prefs.getStringList('read_notification_ids');
      if (savedReadIds != null) {
        _readNotificationIds.addAll(savedReadIds);
      }
      final savedCrmJson = prefs.getString('crm_contacts_map_json');
      if (savedCrmJson != null && savedCrmJson.isNotEmpty) {
        try {
          final Map<String, dynamic> decoded = jsonDecode(savedCrmJson);
          decoded.forEach((k, v) => _crmContactNames[k] = v.toString());
        } catch (_) {}
      }
      _activeSimSlot = prefs.getInt('active_sim_slot') ?? 1;
    } catch (e) {
      debugPrint('Error loading saved preferences: $e');
    }
    if (mustReauthenticate) {
      await purgeUserSession();
    }
    if (!_initCompleter.isCompleted) {
      _initCompleter.complete();
    }
    notifyListeners();
    _pushAutoRecordToNative();
    await fetchDeviceSims();
    if (_isLoggedIn) {
      await refreshProfile();
    }
    if (_isLoggedIn) {
      await _checkWorkSimForSession(); // before the first sync: only the registered SIM's calls
      await fetchDeviceCallLogs();
      await fetchBackendData();
      CallRecordingChannel.retryUploads();
      refreshRecordingSetupStatus();
    }
    _startPeriodicSyncTimer();
  }

  /// GET /auth/me: refreshes name / role / team / daily target from the server.
  /// A 401 AUTH_REQUIRED purges the session through [ApiService.onAuthRequired].
  Future<void> refreshProfile() async {
    if (!_isLoggedIn || _authToken.isEmpty) return;
    final gen = _sessionGeneration;
    final res = await ApiService.fetchMe();
    if (!_isCurrentSession(gen) || res == null || res['success'] != true) return;
    final user = res['user'];
    if (user is Map) _applyUserProfile(Map<String, dynamic>.from(user), keepTrackingNumber: true);
    await _savePreferences();
    notifyListeners();
  }

  void _applyUserProfile(Map<String, dynamic> user, {bool keepTrackingNumber = false}) {
    final name = asString(user['name']);
    if (name.isNotEmpty) _callerName = name;
    _currentUserId = asString(user['id'] ?? user['_id'], _currentUserId);
    _currentUserEmail = asString(user['email']);
    _currentUserRole = asString(user['role'], _currentUserRole).toLowerCase();
    _currentUserTeam = asString(user['team'], _currentUserRole == 'caller' ? 'Telesales Team' : 'Management');
    // The admin can change the target at any time: take the server's value whenever it is sent
    if (user.containsKey('dailyTarget')) {
      final target = asInt(user['dailyTarget'], -1);
      if (target >= 0) _currentUserDailyTarget = target;
    }
    final phone = asString(user['phone']);
    if (phone.isNotEmpty && (!keepTrackingNumber || _verifiedTrackingNumber.isEmpty || _verifiedTrackingNumber.contains('@'))) {
      _verifiedTrackingNumber = phone;
    }
  }

  Timer? _syncPollingTimer;

  /// Poll every 60 s while the app is in the foreground and a user is signed in: profile (daily
  /// target), call counts and notifications. Catches changes the call-log observer missed.
  void _startPeriodicSyncTimer() {
    _syncPollingTimer?.cancel();
    if (!_appInForeground) return;
    _syncPollingTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_isLoggedIn && _appInForeground) {
        refreshProfile();
        _refreshLiveNumbers();
        fetchNotifications();
      }
    });
  }

  /// Re-reads the device call log (which uploads new calls) and the server-counted numbers.
  Future<void> _refreshLiveNumbers() async {
    if (!_isLoggedIn) return;
    if (_isCallerContext) await fetchDeviceCallLogs();
    await _refreshServerStats();
  }

  // Latest call-recording setup state (Accessibility, built-in recorder, last capture) for the dashboard warning
  RecordingSetupStatus? _recordingSetupStatus;
  RecordingSetupStatus? get recordingSetupStatus => _recordingSetupStatus;

  Future<void> refreshRecordingSetupStatus() async {
    if (!Platform.isAndroid || !_isLoggedIn || !_isCallerContext) return;
    final s = await CallRecordingChannel.status(_currentUserId);
    if (s == null) return;
    _recordingSetupStatus = s;
    notifyListeners();
  }

  /// Why calls are probably not being recorded with sound, or null when recording looks fine.
  String? get recordingProblem {
    final s = _recordingSetupStatus;
    if (s == null || !_autoRecordEnabled) return null;
    if (s.nativeRecorderDetected && s.mediaPermission) return null; // the phone's own recordings are uploaded
    if (!s.micPermission) return 'Microphone permission is off, so calls are not recorded.';
    if (!s.accessibilityEnabled && s.usesGoogleDialerOnOemPhone) {
      return 'Turn on the Accessibility permission, or switch to your phone\'s own Phone app with automatic call recording.';
    }
    if (!s.accessibilityEnabled) {
      return s.lastCaptureStatus == 'silent'
          ? 'Your last call was not recorded: Android muted the microphone. Turn on the Accessibility permission.'
          : 'Turn on the Accessibility permission, otherwise Android mutes the microphone and calls are recorded silent.';
    }
    if (s.lastCaptureStatus == 'silent') return 'Your last call was recorded without sound. Open call recording setup.';
    return null;
  }

  static String _syncAckKey(String userId) => 'call_sync_ack_ms_$userId';

  /// Every per-user preference key (removed on logout).
  static const List<String> _perUserPrefKeys = [
    'auth_token',
    'verified_tracking_number',
    'caller_name',
    'current_user_role',
    'current_user_team',
    'current_user_id',
    'current_user_email',
    'current_user_daily_target',
    'user_role',
    'manager_caller_mode',
    'profile_photo_base64',
    'profile_photo_path',
    'login_session_timestamp_ms',
    'initial_setup_timestamp_ms',
    'saved_callbacks_json',
    'lead_status_overrides_json',
    'lead_notes_json',
    'read_notification_ids',
    'crm_contacts_map_json',
    'is_on_duty',
    'duty_start_ms',
  ];

  Future<void> _setOrRemoveString(SharedPreferences prefs, String key, String value, bool keep) async {
    if (keep) {
      await prefs.setString(key, value);
    } else {
      await prefs.remove(key);
    }
  }

  Future<void> _saveChain = Future.value();

  /// Saves run one after another, so a save that started before logout can never land after
  /// the logout's own save (which removes every per-user key).
  Future<void> _savePreferences() {
    _saveChain = _saveChain.then((_) => _writePreferences());
    return _saveChain;
  }

  Future<void> _writePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', _isLoggedIn);
      await prefs.setBool('setup_completed', _setupCompleted);
      await prefs.setBool('auto_record_enabled', _autoRecordEnabled);
      await prefs.setString('sim_tracking_mode', _simTrackingMode.name);
      await prefs.setInt('active_sim_slot', _activeSimSlot);
      if (!_isLoggedIn) {
        // Nothing user-specific may survive a logout.
        for (final k in _perUserPrefKeys) {
          await prefs.remove(k);
        }
        return;
      }
      await prefs.setString('auth_token', _authToken);
      await prefs.setString('verified_tracking_number', _verifiedTrackingNumber);
      await prefs.setString('caller_name', _callerName);
      await prefs.setString('user_role', _currentRole.name);
      await prefs.setString('current_user_role', _currentUserRole);
      await prefs.setString('current_user_team', _currentUserTeam);
      await prefs.setString('current_user_id', _currentUserId);
      await prefs.setString('current_user_email', _currentUserEmail);
      await prefs.setInt('current_user_daily_target', _currentUserDailyTarget);
      await prefs.setBool('manager_caller_mode', _isManagerCallerMode);
      await _setOrRemoveString(prefs, 'profile_photo_base64', _profilePhotoBase64, _profilePhotoBase64.isNotEmpty);
      await _setOrRemoveString(prefs, 'profile_photo_path', _profilePhotoPath, _profilePhotoPath.isNotEmpty);
      if (_loginSessionTimestamp != null) {
        await prefs.setInt('login_session_timestamp_ms', _loginSessionTimestamp!.millisecondsSinceEpoch);
      } else {
        await prefs.remove('login_session_timestamp_ms');
      }
      // Collections are always written (or removed when empty) so deletions persist too.
      await _setOrRemoveString(prefs, 'saved_callbacks_json', jsonEncode(_callbacks.map((c) => c.toMap()).toList()), _callbacks.isNotEmpty);
      await _setOrRemoveString(prefs, 'lead_status_overrides_json', jsonEncode(_leadStatusOverrides), _leadStatusOverrides.isNotEmpty);
      await _setOrRemoveString(prefs, 'lead_notes_json', jsonEncode(_leadNotes), _leadNotes.isNotEmpty);
      await _setOrRemoveString(prefs, 'crm_contacts_map_json', jsonEncode(_crmContactNames), _crmContactNames.isNotEmpty);
      if (_readNotificationIds.isNotEmpty) {
        await prefs.setStringList('read_notification_ids', _readNotificationIds.toList());
      } else {
        await prefs.remove('read_notification_ids');
      }
      await prefs.setBool('is_on_duty', _isOnDuty);
      if (_dutyStartTime != null) {
        await prefs.setInt('duty_start_ms', _dutyStartTime!.millisecondsSinceEpoch);
      } else {
        await prefs.remove('duty_start_ms');
      }
    } catch (e) {
      debugPrint('Error saving preferences: $e');
    }
  }

  Map<String, dynamic>? _backendStats;
  Map<String, dynamic>? get backendStats => _backendStats;
  Map<String, dynamic>? _todayStats; // caller's own numbers for today (daily-target card)
  int _statsRequestSeq = 0; // only the latest stats request may update the screen
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
      final r = (u['role']?.toString() ?? '').toLowerCase();

      // Never show admins to managers
      if (_currentRole == UserRole.manager && r == 'admin') {
        continue;
      }

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
    if (!_isLoggedIn) return;
    final gen = _sessionGeneration;
    try {
      String? phoneParam;
      String? nameParam;
      String? userIdParam;
      String? teamParam;

      if (_isCallerContext) {
        // Caller view (also a manager in caller mode): only this user's own numbers.
        phoneParam = _verifiedTrackingNumber.contains('@') ? null : _verifiedTrackingNumber;
        nameParam = _callerName;
        userIdParam = _currentUserId.isNotEmpty ? _currentUserId : _callerName;
      } else {
        if (_selectedTeamFilter != 'ALL') {
          teamParam = _selectedTeamFilter;
        }
        if (_selectedUserFilter != 'ALL') {
          nameParam = _selectedUserFilter;
          userIdParam = _selectedUserFilter;
        }
      }
      final q = _periodQuery();
      final String? dateParam = q['date'];
      final String? periodParam = q['period'];
      final String? startDateParam = q['startDate'];
      final String? endDateParam = q['endDate'];

      await _refreshServerStats();
      if (!_isCurrentSession(gen)) return;
      final emps = await ApiService.fetchLeaderboard(
        callerPhone: phoneParam,
        callerName: nameParam,
        team: teamParam,
        userId: userIdParam,
        period: periodParam,
        date: dateParam,
        startDate: startDateParam,
        endDate: endDateParam,
        timeFilter: _selectedTimeFilter.toString(),
        loggedInRole: _currentUserRole,
        loggedInTeam: _currentUserTeam,
        loggedInUserId: _currentUserId,
      );
      if (!_isCurrentSession(gen)) return;
      if (emps != null) {
        _teamEmployees = emps;
        final me = _teamEmployees.where((e) => e.id == _currentUserId).toList();
        if (me.isNotEmpty && me.first.dailyTarget != _currentUserDailyTarget) {
          _currentUserDailyTarget = me.first.dailyTarget;
          _savePreferences();
        }
      }

      await _refreshRecordings();
      if (!_isCurrentSession(gen)) return;

      final backendLeads = await ApiService.fetchLeads(
        callerPhone: phoneParam,
        callerName: nameParam,
        team: teamParam,
        userId: userIdParam,
        loggedInRole: _currentUserRole,
        loggedInTeam: _currentUserTeam,
        loggedInUserId: _currentUserId,
      );
      if (!_isCurrentSession(gen)) return;
      if (backendLeads != null) {
        for (var bl in backendLeads) {
          if (bl.id.isEmpty) continue;
          // Apply a local status/note the server has not confirmed yet
          if (_leadStatusOverrides.containsKey(bl.phone)) {
            final st = _leadStatusOverrides[bl.phone]!;
            bl.status = LeadStatus.values.firstWhere((e) => e.name == st, orElse: () => bl.status);
          }
          if (_leadNotes.containsKey(bl.phone)) {
            bl.note = _leadNotes[bl.phone]!;
          }

          final existingIdx = _leads.indexWhere((l) => l.id == bl.id || samePhone(l.phone, bl.phone));
          if (existingIdx != -1) {
            _leads[existingIdx] = bl;
          } else {
            _leads.add(bl);
          }
        }
      }

      await fetchNotifications();
      if (!_isCurrentSession(gen)) return;
      notifyListeners();
    } catch (e) {
      debugPrint('Backend fetch notice: $e');
    }
  }

  /// Reloads the recordings list. A failed request keeps the list already on screen.
  Future<void> _refreshRecordings() async {
    if (!_isLoggedIn) return;
    final gen = _sessionGeneration;
    String? phoneParam;
    String? nameParam;
    String? teamParam;
    String? userIdParam;
    if (_isCallerContext) {
      phoneParam = _verifiedTrackingNumber.contains('@') ? null : _verifiedTrackingNumber;
      nameParam = _callerName;
      userIdParam = _currentUserId;
    } else {
      if (_selectedTeamFilter != 'ALL') teamParam = _selectedTeamFilter;
      if (_selectedUserFilter != 'ALL') {
        nameParam = _selectedUserFilter;
        userIdParam = _selectedUserFilter;
      }
    }
    final recs = await ApiService.fetchRecordings(
      callerPhone: phoneParam,
      callerName: nameParam,
      team: teamParam,
      userId: userIdParam,
      loggedInRole: _isManagerCallerMode ? 'caller' : _currentUserRole,
      loggedInTeam: _currentUserTeam,
      loggedInUserId: _currentUserId,
    );
    if (recs == null || !_isCurrentSession(gen)) return;
    // Keep the playing state of a recording that is still in the list
    final playingId = _recordings.where((r) => r.isPlaying).map((r) => r.id).firstOrNull;
    for (final r in recs) {
      if (r.id == playingId) {
        r.isPlaying = true;
        r.progress = _recordings.firstWhere((x) => x.id == playingId).progress;
      }
    }
    _recordings
      ..clear()
      ..addAll(recs);
    notifyListeners();
  }

  // Caller Notifications
  final List<NotificationItem> _notifications = [];
  int _unreadNotificationCount = 0;
  List<NotificationItem> get notifications => _notifications;
  int get unreadNotificationCount => _unreadNotificationCount;

  String _notificationSignature(Iterable<NotificationItem> items) =>
      items.map((n) => '${n.id}:${n.isRead ? 1 : 0}').join('|');

  Future<void> fetchNotifications() async {
    if (!_isLoggedIn) return;
    final gen = _sessionGeneration;
    try {
      final res = await ApiService.fetchCallerNotifications(
        phone: _verifiedTrackingNumber,
        name: _callerName,
      );
      if (!_isCurrentSession(gen)) return;
      if (res != null && res['success'] == true && res['notifications'] is List) {
        final fresh = <NotificationItem>[];
        for (var item in res['notifications'] as List) {
          if (item is Map) {
            final notif = NotificationItem.fromJson(Map<String, dynamic>.from(item));
            if (_readNotificationIds.contains(notif.id)) {
              notif.isRead = true;
            }
            fresh.add(notif);
          }
        }
        if (_notificationSignature(fresh) == _notificationSignature(_notifications)) return;
        _notifications
          ..clear()
          ..addAll(fresh);
        _unreadNotificationCount = _notifications.where((n) => !n.isRead).length;
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
      _readNotificationIds.add(notifId);
      if (_unreadNotificationCount > 0) _unreadNotificationCount--;
      _savePreferences();
      notifyListeners();
    }
    await ApiService.markNotificationRead(notifId);
  }

  Future<void> markAllNotificationsRead() async {
    for (var n in _notifications) {
      n.isRead = true;
      _readNotificationIds.add(n.id);
    }
    _unreadNotificationCount = 0;
    _savePreferences();
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
  final List<CallLogModel> _callLogs = []; // work-SIM calls since login
  final List<CallLogModel> _allDeviceCalls = []; // every call since login (used to match recordings)
  List<CallLogModel> get allCallLogs => _callLogs;

  Future<void> fetchDeviceCallLogs() async {
    if (!_isLoggedIn || !_isCallerContext) {
      if (_callLogs.isNotEmpty || _allDeviceCalls.isNotEmpty) {
        _callLogs.clear();
        _allDeviceCalls.clear();
        notifyListeners();
      }
      return;
    }
    final gen = _sessionGeneration;
    try {
      final sessionMs = _loginSessionTimestamp?.millisecondsSinceEpoch;
      if (sessionMs == null) return;
      // Native side returns only calls since login (read on a background thread)
      final List<dynamic>? rawLogs = await _telephonyChannel.invokeMethod('getCallLogs', {'since': sessionMs - 5000});
      if (!_isCurrentSession(gen)) return;
      if (rawLogs != null) {
        final List<CallLogModel> everything = [];
        final List<CallLogModel> realLogs = [];

        for (var raw in rawLogs) {
          if (raw is! Map) continue;
          final map = Map<String, dynamic>.from(raw);
          final timestampMs = asInt(map['timestamp'], -1);
          if (timestampMs < 0 || timestampMs < sessionMs - 5000) {
            continue; // Strictly skip all personal calls prior to the login work session
          }
          final simSlot = asInt(map['simSlot']);
          final phoneNum = asString(map['phoneNumber']);
          final key = last10Digits(phoneNum);

          var resolvedName = asString(map['contactName'], 'Unknown');
          var isCrm = false;
          if (_crmContactNames.containsKey(key)) {
            resolvedName = _crmContactNames[key]!;
            isCrm = true;
          }

          final model = CallLogModel(
            id: asString(map['id'], '$timestampMs'),
            contactName: resolvedName,
            phoneNumber: phoneNum,
            type: callTypeFromNative(map['type']?.toString()),
            duration: Duration(seconds: asInt(map['duration'])),
            timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
            simSlot: simSlot,
            isCrmContact: isCrm,
          );
          everything.add(model);
          // PERSONAL CALL ISOLATION: calls identified on the personal SIM never leave the device
          if (_isWorkSim(simSlot)) realLogs.add(model);
        }
        _allDeviceCalls
          ..clear()
          ..addAll(everything);
        _callLogs
          ..clear()
          ..addAll(realLogs);
        _syncLeadsFromCallLogs();
        _syncCallbacksFromCallLogs();
        notifyListeners();
        if (_callLogs.isNotEmpty) {
          _syncCallsToServer();
        }
      }
    } catch (e) {
      debugPrint('Error fetching device call logs: $e');
    }
  }

  // Uploads device calls to the server. Only calls newer than the last timestamp the server
  // acknowledged are sent (persisted per user). One upload at a time; a request made meanwhile runs right after.
  bool _callSyncInFlight = false;
  bool _callSyncPending = false;
  DateTime? _lastCallSyncAck;
  DateTime? _lastCallSyncAt; // when the last sync request succeeded
  DateTime? get lastCallSyncAt => _lastCallSyncAt;

  Future<void> _syncCallsToServer() async {
    if (_callSyncInFlight) {
      _callSyncPending = true;
      return;
    }
    if (_currentUserId.isEmpty) return;
    _callSyncInFlight = true;
    final gen = _sessionGeneration;
    try {
      do {
        _callSyncPending = false;
        final batch = callsNewerThan(_callLogs, _lastCallSyncAck);
        if (batch.isEmpty) break;
        final inserted = await ApiService.syncCallLogs(
          batch,
          callerId: _currentUserId,
          callerName: _callerName,
          callerPhone: _verifiedTrackingNumber,
        );
        if (!_isCurrentSession(gen)) return;
        if (inserted < 0) break; // failed: retried on the next call-log change / app start
        _lastCallSyncAt = DateTime.now();
        final newest = newestTimestamp(batch);
        if (newest != null) {
          _lastCallSyncAck = newest;
          try {
            final prefs = await SharedPreferences.getInstance();
            if (_isCurrentSession(gen)) {
              await prefs.setInt(_syncAckKey(_currentUserId), newest.millisecondsSinceEpoch);
            }
          } catch (_) {}
        }
        // New calls stored: refresh the server-counted numbers so the app matches the admin web
        if (inserted > 0) await _refreshServerStats();
      } while (_callSyncPending && _isLoggedIn && _isCurrentSession(gen));
    } finally {
      _callSyncInFlight = false;
    }
  }

  // Query values for the selected period: {period} or {date} or {startDate, endDate}
  Map<String, String?> _periodQuery() {
    String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (_selectedDateRange != null) {
      return {'startDate': ymd(_selectedDateRange!.start), 'endDate': ymd(_selectedDateRange!.end)};
    }
    if (_selectedCustomDate != null) return {'date': ymd(_selectedCustomDate!)};
    return {'period': const ['today', 'week', 'month'][_selectedTimeFilter.clamp(0, 2)]};
  }

  /// Who the dashboard numbers are for: the signed-in caller (also a manager in caller mode), or the
  /// manager's selected team / user.
  Map<String, String?> _statsScope() {
    if (_isCallerContext) {
      return {
        'phone': _verifiedTrackingNumber.contains('@') ? null : _verifiedTrackingNumber,
        'name': _callerName,
        'userId': _currentUserId.isNotEmpty ? _currentUserId : _callerName,
        'team': null,
      };
    }
    return {
      'phone': null,
      'name': _selectedUserFilter != 'ALL' ? _selectedUserFilter : null,
      'userId': _selectedUserFilter != 'ALL' ? _selectedUserFilter : null,
      'team': _selectedTeamFilter != 'ALL' ? _selectedTeamFilter : null,
    };
  }

  /// Server-counted numbers for the selected period and, for a caller, for today (the daily-target
  /// card always shows today). Only the latest request may update the screen.
  Future<void> _refreshServerStats() async {
    if (!_isLoggedIn) return;
    final gen = _sessionGeneration;
    final scope = _statsScope();
    final q = _periodQuery();
    final isToday = q['period'] == 'today';
    Future<Map<String, dynamic>?> fetch(Map<String, String?> period, String timeFilter) => ApiService.fetchDashboardStats(
          callerPhone: scope['phone'],
          callerName: scope['name'],
          team: scope['team'],
          userId: scope['userId'],
          period: period['period'],
          date: period['date'],
          startDate: period['startDate'],
          endDate: period['endDate'],
          timeFilter: timeFilter,
          // A manager in caller mode is scoped like a caller on the server.
          loggedInRole: _isManagerCallerMode ? 'caller' : _currentUserRole,
          loggedInTeam: _currentUserTeam,
          loggedInUserId: _currentUserId,
        );
    final statsRequest = ++_statsRequestSeq;
    final results = await Future.wait([
      fetch(q, _selectedTimeFilter.toString()),
      if (!isToday && _isCallerContext) fetch(const {'period': 'today'}, '0'),
    ]);
    // A slower response for a period the user already switched away from must not overwrite newer numbers
    if (!_isLoggedIn || !_isCurrentSession(gen) || statsRequest != _statsRequestSeq) return;
    final stats = results[0];
    if (stats != null) {
      _backendStats = stats;
      if (stats['teams'] is List) {
        final rawTeams = (stats['teams'] as List).map((t) => t.toString()).toList();
        final filtered = rawTeams.where((t) =>
          t != 'ALL' &&
          t != 'ALL TEAMS' &&
          t != 'BD TEAM - AE' &&
          t != 'BDE' &&
          t != 'Telesales Mumbai'
        ).toList();
        _availableTeams = ['ALL', ...(filtered.isNotEmpty ? filtered : ['Telesales Team', 'Management'])];
      }
      if (stats['allUsers'] is List) {
        _allUsers = (stats['allUsers'] as List).whereType<Map>().map((u) => Map<String, dynamic>.from(u)).toList();
      }
    }
    final today = isToday ? stats : (results.length > 1 ? results[1] : null);
    if (today != null && _isCallerContext) _todayStats = today;
    notifyListeners();
  }

  Future<void> fetchDeviceSims() async {
    try {
      final List<dynamic>? rawList = await _telephonyChannel.invokeMethod('getSimCards');
      if (rawList != null && rawList.isNotEmpty) {
        _detectedSims = rawList
            .map((e) => SimCardInfo.fromMap(e as Map<dynamic, dynamic>))
            .toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Platform channel getSimCards info: $e');
    }
  }

  /// Checks that the registered number is one of the SIMs in this phone.
  /// - positive match: tracking switches to that SIM;
  /// - numbers unreadable (common on Android 10+) or none match: still valid, the saved tracking
  ///   mode is kept. The number a phone reports for a SIM is often stale, blank or wrong (ported
  ///   numbers, eSIM, some carriers), so it must never block a registered caller who signed in
  ///   with the right password.
  Future<Map<String, dynamic>> verifyRegisteredSimCard(String registeredPhone) async {
    await fetchDeviceSims();
    final last10Reg = last10Digits(registeredPhone);
    if (last10Reg.length != 10) {
      return {'isValid': true, 'matched': false};
    }

    final readable = _detectedSims.where((s) => last10Digits(s.phoneNumber).length == 10).toList();
    if (readable.isEmpty) {
      return {'isValid': true, 'matched': false};
    }
    for (final sim in readable) {
      if (samePhone(sim.phoneNumber, last10Reg)) {
        _simTrackingMode = sim.slotIndex == 1 ? SimTrackingMode.sim2Only : SimTrackingMode.sim1Only;
        _activeSimSlot = sim.slotIndex + 1;
        return {'isValid': true, 'matched': true, 'slotIndex': sim.slotIndex};
      }
    }
    debugPrint('SIM check: registered $last10Reg not among the numbers this phone reports; continuing');
    return {'isValid': true, 'matched': false};
  }

  Future<Map<String, dynamic>> validateAndSetTrackingNumber(String inputPhone, int slotIndex) async {
    final last10 = last10Digits(inputPhone);

    if (last10.length != 10 || !RegExp(r'^[6-9]\d{9}$').hasMatch(last10)) {
      return {'isValid': false, 'message': 'Please enter a valid 10-digit mobile number.'};
    }
    try {
      final verifyRes = await ApiService.checkPhoneRegistered(last10);
      if (verifyRes == null) {
        final why = ApiService.lastNetworkError;
        return {
          'isValid': false,
          'message': 'Could not reach the AskEVA server.'
              '${why.isNotEmpty ? '\n\nReason: $why' : ''}'
              '\n\nTip: open https://telesales.askeva.io/api/health in Chrome on this phone. If it opens, allow AskEVA '
              'to use Wi-Fi and mobile data in Settings → Apps → AskEVA.',
        };
      }
      if (verifyRes['success'] != true) {
        return {
          'isValid': false,
          'message': verifyRes['message']?.toString() ?? 'Mobile number \'$last10\' is not registered in the database. Please contact your manager or admin to add your account.'
        };
      }
      _callerName = verifyRes['user']?['name']?.toString() ?? _callerName;
    } catch (e) {
      debugPrint('DB verification error: $e');
      return {
        'isValid': false,
        'message': 'Verification could not be completed ($e). Please try again.'
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
    if (_detectedSims.isEmpty) return 'MONITORING: ALL CALLS';
    switch (_simTrackingMode) {
      case SimTrackingMode.sim1Only:
        final s1 = _detectedSims.isNotEmpty ? _detectedSims[0].displayName : 'SIM 1';
        return 'ACTIVE WORK SIM: $s1';
      case SimTrackingMode.sim2Only:
        final s2 = _detectedSims.length > 1 ? _detectedSims[1].displayName : 'SIM 2';
        return 'ACTIVE WORK SIM: $s2';
      case SimTrackingMode.bothSims:
        return 'MONITORING: ALL WORK SIMs';
    }
  }

  /// Short label of the work SIM, e.g. "SIM 2", or "ALL SIMS".
  String get workSimShortLabel {
    switch (_simTrackingMode) {
      case SimTrackingMode.sim1Only:
        return 'SIM 1';
      case SimTrackingMode.sim2Only:
        return 'SIM 2';
      case SimTrackingMode.bothSims:
        return 'ALL SIMS';
    }
  }

  /// 0-based SIM slot used for outgoing calls.
  int get workSimSlotIndex => _simTrackingMode == SimTrackingMode.sim2Only ? 1 : 0;

  void completeSetup({required SimTrackingMode mode, String? verifiedNumber, String? callerName}) {
    _simTrackingMode = mode;
    if (verifiedNumber != null && verifiedNumber.isNotEmpty) {
      _verifiedTrackingNumber = verifiedNumber;
    }
    if (callerName != null && callerName.isNotEmpty) {
      _callerName = callerName;
    }
    _setupCompleted = true;
    _savePreferences();
    notifyListeners();
  }

  void setSimTrackingMode(SimTrackingMode mode) {
    _simTrackingMode = mode;
    // A specific SIM picked in settings becomes this caller's remembered work SIM
    if (_isLoggedIn && mode != SimTrackingMode.bothSims) {
      _rememberWorkSim(_verifiedTrackingNumber, mode == SimTrackingMode.sim2Only ? 2 : 1);
    }
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

  /// Signs out and forgets everything that belongs to the user. Always await it.
  Future<void> purgeUserSession() async {
    _sessionGeneration++; // in-flight requests of this session are ignored from now on
    ApiService.clearToken();
    _isLoggedIn = false;
    _setupCompleted = true; // Setup (permissions / SIM) is per device, not per user
    _authToken = '';
    _activeTabIndex = 0;
    _loginSessionTimestamp = null;

    // Identity
    _verifiedTrackingNumber = '';
    _callerName = '';
    _currentUserId = '';
    _currentUserEmail = '';
    _currentUserRole = 'caller';
    _currentUserTeam = 'Telesales Team';
    _currentUserDailyTarget = kDefaultDailyTarget;
    _currentRole = UserRole.caller;
    _isManagerCallerMode = false;
    _profilePhotoBase64 = '';
    _profilePhotoPath = '';

    // Data
    _backendStats = null; // never show the previous user's numbers to the next login
    _todayStats = null;
    _recordingSetupStatus = null;
    _statsRequestSeq++;
    _teamEmployees = [];
    _allUsers = [];
    _availableTeams = ['ALL', 'Telesales Team', 'Management'];
    _selectedEmployee = null;
    _callLogs.clear();
    _allDeviceCalls.clear();
    _leads.clear();
    _leadStatusOverrides.clear();
    _leadNotes.clear();
    _crmContactNames.clear();
    _callbacks.clear();
    _recordings.clear();
    _notifications.clear();
    _unreadNotificationCount = 0;
    _readNotificationIds.clear();
    _lastCallSyncAck = null;
    _lastCallSyncAt = null;
    _callSyncPending = false;
    _needsWorkSimChoice = false;
    _pendingSimChoice = null;

    // Filters
    _selectedTeamFilter = 'ALL';
    _selectedUserFilter = 'ALL';
    _selectedTimeFilter = 0;
    _selectedCustomDate = null;
    _selectedDateRange = null;
    _callFilter = 'ALL';
    _callQualityFilter = 0;
    _leadFilter = 'ALL';

    // Duty / breaks / session
    _isOnDuty = false;
    _dutyStartTime = null;
    _isOnBreak = false;
    _currentBreakType = '';
    _breakStartTime = null;
    _breakLogs.clear();
    _sessionCallTimer?.cancel();
    _sessionCallTimer = null;
    _sessionQueue = [];
    _sessionIndex = 0;
    _activeCallLead = null;
    _callTimerSeconds = 0;
    _sessionCallStartedAt = null;
    _sessionCallEndedAt = null;
    _callLogDebounce?.cancel();

    // Playback
    _stopPlaybackPolling();
    _telephonyChannel.invokeMethod('stopAudio').catchError((_) => null);

    // Stops the call monitor: nothing is recorded or uploaded without a session. Recordings still
    // queued stay on the device and upload when the same user signs in again.
    _pendingUploadCount = 0;
    _pushAutoRecordToNative();
    await _savePreferences();
    notifyListeners();
  }

  /// Stores a successful login response and starts the session.
  Future<void> _beginSession(Map<String, dynamic> res, Map<String, dynamic> user) async {
    _sessionGeneration++;
    _authToken = asString(res['token'] ?? user['token']);
    ApiService.setToken(_authToken);
    _applyUserProfile(user);
    _isLoggedIn = true;
    _setupCompleted = true;
    _loginSessionTimestamp = DateTime.now();
    final syncAck = (await SharedPreferences.getInstance()).getInt(_syncAckKey(_currentUserId));
    _lastCallSyncAck = syncAck != null ? DateTime.fromMillisecondsSinceEpoch(syncAck) : null;
    if (!_isOnDuty) {
      _isOnDuty = true;
      _dutyStartTime = DateTime.now();
    }
  }

  /// Token of a caller who signed in but still has to link a phone number.
  Map<String, dynamic>? _pendingPhoneLink;

  Future<Map<String, dynamic>> performLogin({
    required String username,
    required String password,
    required UserRole role,
  }) async {
    try {
      final asManager = role == UserRole.manager;
      final res = await ApiService.login(
        identifier: username,
        password: password,
        asManager: asManager,
        simSlot: asManager ? null : _activeSimSlot,
      );
      if (res == null) {
        return {'success': false, 'message': 'Could not reach the server. Check your internet connection.'};
      }
      if (res['success'] != true || res['user'] is! Map) {
        return {'success': false, 'message': res['message']?.toString() ?? 'Invalid credentials.'};
      }
      final user = Map<String, dynamic>.from(res['user'] as Map);
      final token = asString(res['token'] ?? user['token']);
      if (token.isEmpty) {
        return {'success': false, 'message': 'Server did not return a session token. Please update the backend.'};
      }
      final userRole = asString(user['role'], asManager ? 'manager' : 'caller').toLowerCase();
      if (userRole == 'admin') {
        return {
          'success': false,
          'message': 'Admin accounts must use the AskEVA Web Admin Portal. Mobile app is reserved for Managers and Callers.'
        };
      }

      if (asManager) {
        if (userRole == 'caller') {
          return {
            'success': false,
            'message': 'This account is registered as a Caller Agent. Please switch to the Caller tab to log in.'
          };
        }
        await _beginSession(res, user);
        _currentRole = UserRole.manager;
        _isManagerCallerMode = false;
        await _savePreferences();
        _pushAutoRecordToNative();
        await fetchBackendData();
        _startPeriodicSyncTimer();
        refreshRecordingSetupStatus();
        notifyListeners();
        return {'success': true, 'message': 'Manager authentication successful'};
      }

      // Caller tab: callers, or managers who want to work as a caller
      final regPhone = asString(user['phone']);
      if (regPhone.isEmpty) {
        // Signed in, but no number linked yet: keep the token only in memory until the phone is linked.
        _pendingPhoneLink = {'res': res, 'user': user};
        ApiService.setToken(token);
        return {
          'success': false,
          'requiresPhoneInput': true,
          'user': {'name': user['name'], 'email': user['email']},
          'message': 'Please verify your SIM card tracking phone number to complete setup.'
        };
      }

      // Verify the authorized SIM card is inside the phone
      final simCheck = await verifyRegisteredSimCard(regPhone);
      if (simCheck['isValid'] != true) {
        return {
          'success': false,
          'message': simCheck['message'] ?? 'The registered work SIM card (+91 $regPhone) is not detected in this phone.'
        };
      }

      // Only the registered number's SIM is tracked: find it, or let the caller pick it
      final workSlot = await _resolveWorkSimSlot(regPhone, simCheck);
      if (workSlot == null) {
        _pendingSimChoice = {'res': res, 'user': user, 'role': userRole, 'phone': regPhone};
        return {
          'success': false,
          'requiresSimChoice': true,
          'phone': last10Digits(regPhone),
          'message': 'Choose the SIM that holds your registered number.',
        };
      }
      if (workSlot > 0) _applyWorkSim(workSlot);
      return await _finishCallerLogin(res, user, userRole);
    } catch (e) {
      debugPrint('TeleProvider.performLogin notice: $e');
    }
    return {'success': false, 'message': 'Could not reach server. Check backend connection.'};
  }

  // ---- Work SIM: the SIM that holds the caller's registered number ----
  // Remembered per registered number (device setting that survives logout), so one caller's choice is
  // never applied to another caller who signs in on the same phone.
  static String _workSimKey(String phone) => 'work_sim_slot_${last10Digits(phone)}';

  /// Login waiting for the caller to pick their SIM (dual-SIM phone that cannot tell by itself).
  Map<String, dynamic>? _pendingSimChoice;

  /// A signed-in caller on a dual-SIM phone whose work SIM is not known yet: the app asks once.
  bool _needsWorkSimChoice = false;
  bool get needsWorkSimChoice => _needsWorkSimChoice;

  /// 1-based slot of the registered number's SIM: the SIM whose number matches, the caller's
  /// remembered choice, or the phone's only SIM. -1 = SIM info not readable (tracking unchanged).
  /// Null = dual-SIM phone that cannot tell: the caller has to pick.
  Future<int?> _resolveWorkSimSlot(String registeredPhone, Map<String, dynamic> simCheck) async {
    if (last10Digits(registeredPhone).length != 10) return -1;
    final prefs = await SharedPreferences.getInstance();
    final key = _workSimKey(registeredPhone);
    final matched = simCheck['matched'] == true && simCheck['slotIndex'] is int ? (simCheck['slotIndex'] as int) + 1 : null;
    if (matched != null) await prefs.setInt(key, matched);
    return pickWorkSimSlot(
      matchedSlot: matched,
      savedSlot: prefs.getInt(key),
      detectedSlots: _detectedSims.map((s) => s.slotIndex + 1).toSet(),
    );
  }

  void _applyWorkSim(int slot) {
    _activeSimSlot = slot;
    _simTrackingMode = slot == 2 ? SimTrackingMode.sim2Only : SimTrackingMode.sim1Only;
  }

  Future<void> _rememberWorkSim(String phone, int slot) async {
    if (last10Digits(phone).length != 10 || (slot != 1 && slot != 2)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_workSimKey(phone), slot);
  }

  Future<Map<String, dynamic>> _finishCallerLogin(Map<String, dynamic> res, Map<String, dynamic> user, String userRole) async {
    await _beginSession(res, user);
    _currentRole = UserRole.caller;
    _isManagerCallerMode = userRole == 'manager' || userRole == 'jr_manager';
    _needsWorkSimChoice = false;
    await _savePreferences();
    _pushAutoRecordToNative();
    await fetchDeviceCallLogs();
    await fetchBackendData();
    _startPeriodicSyncTimer();
    refreshRecordingSetupStatus();
    notifyListeners();
    return {'success': true, 'message': 'Caller authentication successful'};
  }

  /// Completes a login that asked the caller which SIM holds the registered number (1 or 2).
  Future<Map<String, dynamic>> completeLoginWithWorkSim(int slot) async {
    final p = _pendingSimChoice;
    if (p == null) return {'success': false, 'message': 'Session expired. Please sign in again.'};
    _pendingSimChoice = null;
    await _rememberWorkSim(asString(p['phone']), slot);
    _applyWorkSim(slot);
    return _finishCallerLogin(
      Map<String, dynamic>.from(p['res'] as Map),
      Map<String, dynamic>.from(p['user'] as Map),
      asString(p['role'], 'caller'),
    );
  }

  void cancelPendingSimChoice() {
    if (!_isLoggedIn) _pendingSimChoice = null;
  }

  /// Signed-in caller picked their work SIM (1 or 2): only that SIM's calls are tracked from now on.
  Future<void> setWorkSimForRegisteredNumber(int slot) async {
    await _rememberWorkSim(_verifiedTrackingNumber, slot);
    _applyWorkSim(slot);
    _needsWorkSimChoice = false;
    await _savePreferences();
    notifyListeners();
    await fetchDeviceCallLogs(); // re-filter the list for the chosen SIM
  }

  /// On app start: make sure the tracked SIM is this caller's registered SIM (not an old setting).
  Future<void> _checkWorkSimForSession() async {
    if (!_isLoggedIn || !_isCallerContext || last10Digits(_verifiedTrackingNumber).length != 10) return;
    final check = await verifyRegisteredSimCard(_verifiedTrackingNumber);
    final slot = await _resolveWorkSimSlot(_verifiedTrackingNumber, check);
    if (slot == null) {
      _needsWorkSimChoice = true;
      notifyListeners();
      return;
    }
    _needsWorkSimChoice = false;
    if (slot > 0) {
      final before = _simTrackingMode;
      _applyWorkSim(slot);
      if (before != _simTrackingMode) {
        await _savePreferences();
        notifyListeners();
      }
    }
  }

  /// Links the signed-in caller's own number (POST /auth/link-phone with the session token) and
  /// completes the login started by [performLogin].
  Future<Map<String, dynamic>> linkAndVerifySimPhone({required String inputPhone}) async {
    final last10 = last10Digits(inputPhone);
    if (last10.length != 10 || !RegExp(r'^[6-9]\d{9}$').hasMatch(last10)) {
      return {'success': false, 'message': 'Please enter a valid 10-digit mobile number.'};
    }
    final pending = _pendingPhoneLink;
    if (pending == null) {
      return {'success': false, 'message': 'Session expired. Please sign in again.'};
    }

    // 1. Verify against the SIM cards in this phone (when the numbers are readable)
    final simCheck = await verifyRegisteredSimCard(last10);
    if (simCheck['isValid'] == false) {
      return {'success': false, 'message': simCheck['message']};
    }

    // 2. Link the number to the signed-in account
    final linkRes = await ApiService.linkPhone(phone: last10);
    if (linkRes == null) {
      return {'success': false, 'message': 'Could not reach the server. Check your internet connection.'};
    }
    if (linkRes['success'] != true) {
      return {'success': false, 'message': linkRes['message']?.toString() ?? 'Failed to link mobile number.'};
    }

    final user = Map<String, dynamic>.from(pending['user'] as Map);
    final linkedUser = linkRes['user'];
    if (linkedUser is Map) user.addAll(Map<String, dynamic>.from(linkedUser));
    user['phone'] = asString(user['phone']).isNotEmpty ? user['phone'] : last10;
    _pendingPhoneLink = null;

    final res = Map<String, dynamic>.from(pending['res'] as Map);
    final role = asString(user['role'], 'caller').toLowerCase();
    // Only the registered number's SIM is tracked: find it, or let the caller pick it
    final workSlot = await _resolveWorkSimSlot(last10, simCheck);
    if (workSlot == null) {
      _pendingSimChoice = {'res': res, 'user': user, 'role': role, 'phone': last10};
      return {
        'success': false,
        'requiresSimChoice': true,
        'phone': last10,
        'message': 'Choose the SIM that holds your registered number.',
      };
    }
    if (workSlot > 0) _applyWorkSim(workSlot);
    final done = await _finishCallerLogin(res, user, role);
    return {...done, 'message': 'Mobile SIM number linked and verified successfully!'};
  }

  /// Abandon a login that is waiting for phone linking.
  void cancelPendingPhoneLink() {
    if (_pendingPhoneLink != null && !_isLoggedIn) {
      _pendingPhoneLink = null;
      ApiService.clearToken();
    }
  }

  Future<void> logout() async {
    // Before the token is cleared: the dashboard turns this user offline immediately
    await ApiService.logout();
    await purgeUserSession();
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
    var list = simTrackedCallLogs;
    if (_callFilter == 'INCOMING') {
      list = list.where((c) => c.type == CallType.incoming).toList();
    } else if (_callFilter == 'OUTGOING') {
      list = list.where((c) => c.type == CallType.outgoing).toList();
    } else if (_callFilter == 'MISSED') {
      list = list.where((c) => c.type == CallType.missed).toList();
    } else if (_callFilter == 'REJECTED') {
      list = list.where((c) => c.type == CallType.rejected).toList();
    } else if (_callFilter == 'NEVER' || _callFilter == 'NO_PICKUP') {
      list = list.where((c) => c.duration.inSeconds == 0).toList();
    }

    if (_callQualityFilter == 1) {
      list = list.where((c) => c.duration.inSeconds > 0 && c.duration.inSeconds < 120).toList();
    } else if (_callQualityFilter == 2) {
      list = list.where((c) => c.duration.inSeconds >= 120 && c.duration.inSeconds <= 300).toList();
    } else if (_callQualityFilter == 3) {
      list = list.where((c) => c.duration.inSeconds > 300).toList();
    } else if (_callQualityFilter == 4) {
      list = list.where((c) => c.duration.inSeconds == 0 || c.type == CallType.missed || c.type == CallType.rejected).toList();
    }

    return list;
  }

  Map<String, dynamic>? get mostRepeatedCallToday {
    final now = DateTime.now();
    final todayLogs = simTrackedCallLogs.where((c) =>
        c.timestamp.year == now.year &&
        c.timestamp.month == now.month &&
        c.timestamp.day == now.day &&
        c.phoneNumber.isNotEmpty).toList();

    if (todayLogs.isEmpty) return null;

    final Map<String, List<CallLogModel>> grouped = {};
    for (var c in todayLogs) {
      final clean = c.phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
      final last10 = clean.length >= 10 ? clean.substring(clean.length - 10) : clean;
      grouped.putIfAbsent(last10, () => []).add(c);
    }

    String? maxKey;
    int maxCount = 0;
    for (var entry in grouped.entries) {
      if (entry.value.length > maxCount) {
        maxCount = entry.value.length;
        maxKey = entry.key;
      }
    }

    if (maxKey == null || maxCount <= 1) {
      if (todayLogs.isNotEmpty) {
        final first = todayLogs.first;
        return {
          'name': first.contactName != 'Unknown' ? first.contactName : first.phoneNumber,
          'phone': first.phoneNumber,
          'count': 1,
          'durationStr': first.durationFormatted,
        };
      }
      return null;
    }

    final calls = grouped[maxKey]!;
    final first = calls.first;
    int totalSec = 0;
    for (var c in calls) {
      totalSec += c.duration.inSeconds;
    }
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    final durStr = m > 0 ? '${m}m ${s}s' : '${s}s';

    return {
      'name': first.contactName != 'Unknown' ? first.contactName : first.phoneNumber,
      'phone': first.phoneNumber,
      'count': maxCount,
      'durationStr': durStr,
    };
  }

  CallLogModel? get longestCallToday {
    final now = DateTime.now();
    final todayLogs = simTrackedCallLogs.where((c) =>
        c.timestamp.year == now.year &&
        c.timestamp.month == now.month &&
        c.timestamp.day == now.day &&
        c.duration.inSeconds > 0).toList();

    if (todayLogs.isEmpty) return null;
    todayLogs.sort((a, b) => b.duration.inSeconds.compareTo(a.duration.inSeconds));
    return todayLogs.first;
  }

  // Call counts for the selected period, as counted by the server over every synced call.
  // These are the same numbers the admin web shows. The on-device log is only a fallback
  // until the first server response arrives (e.g. offline).
  int _serverCount(String key, int deviceValue) {
    final v = _backendStats?[key];
    return v is num ? v.toInt() : deviceValue;
  }

  // Today's numbers for the daily-target card, whatever period the metrics below show. Server-counted
  // (same as the admin web); a call the phone logged but has not uploaded yet is never hidden.
  List<CallLogModel> get _deviceTodayLogs {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return _callLogs.where((c) {
      if (_simTrackingMode == SimTrackingMode.sim1Only && c.simSlot != 1) return false;
      if (_simTrackingMode == SimTrackingMode.sim2Only && c.simSlot != 2) return false;
      return !c.timestamp.isBefore(todayStart);
    }).toList();
  }

  int _todayCount(String key, int deviceValue) {
    final v = _todayStats?[key];
    return v is num && v.toInt() > deviceValue ? v.toInt() : deviceValue;
  }

  int get todayTotalCalls => _todayCount('totalCalls', _deviceTodayLogs.length);
  int get todayConnectedCalls => _todayCount('connectedCalls', _deviceTodayLogs.where((c) => c.duration.inSeconds > 0).length);
  Duration get todayTalkTime => Duration(
      seconds: _todayCount('talkSeconds', _deviceTodayLogs.fold<int>(0, (sum, c) => sum + c.duration.inSeconds)));

  int get totalCalls => _serverCount('totalCalls', trackedTotalCalls);
  int get connectedCalls => _serverCount('connectedCalls', trackedConnectedCalls);
  int get incomingCalls => _serverCount('incoming', trackedIncomingCalls);
  int get outgoingCalls => _serverCount('outgoing', trackedOutgoingCalls);
  int get missedCalls => _serverCount('missed', trackedMissedCalls);
  int get rejectedCalls => _serverCount('rejected', trackedRejectedCalls);
  int get neverAttendedCalls => _serverCount('neverAttended', trackedNeverAttendedCalls);
  int get uniqueCalls => _serverCount('uniqueClients', trackedUniqueCalls);
  Duration get totalTalkTime => Duration(seconds: _serverCount('talkSeconds', trackedTotalTalkTime.inSeconds));

  String get talkTimeFormatted => _formatTalkTime(totalTalkTime);

  String get averageTalkTimeFormatted {
    final connected = connectedCalls;
    final avg = connected == 0 ? Duration.zero : Duration(seconds: totalTalkTime.inSeconds ~/ connected);
    final m = avg.inMinutes;
    final s = avg.inSeconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  String get selectedPeriodLabel {
    if (_selectedDateRange != null) return 'CUSTOM RANGE';
    if (_selectedCustomDate != null) {
      return '${_selectedCustomDate!.day.toString().padLeft(2, '0')}/${_selectedCustomDate!.month.toString().padLeft(2, '0')}/${_selectedCustomDate!.year}';
    }
    switch (_selectedTimeFilter) {
      case 1:
        return 'THIS WEEK';
      case 2:
        return 'THIS MONTH';
      default:
        return 'TODAY';
    }
  }

  static String _formatTalkTime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  // On-device counts (fallback). Same definitions as the server:
  // incoming = received / missed / declined, missed = unanswered incoming,
  // rejected = declined or unanswered outgoing, never attended = missed + rejected.
  bool _isInbound(CallLogModel c) => c.type == CallType.incoming || c.type == CallType.missed || c.type == CallType.rejected;
  int get trackedTotalCalls => simTrackedCallLogs.length;
  int get trackedConnectedCalls => simTrackedCallLogs.where((c) => c.duration.inSeconds > 0).length;
  int get trackedIncomingCalls => simTrackedCallLogs.where(_isInbound).length;
  int get trackedOutgoingCalls => simTrackedCallLogs.where((c) => !_isInbound(c)).length;
  int get trackedMissedCalls => simTrackedCallLogs.where((c) => c.duration.inSeconds == 0 && (c.type == CallType.incoming || c.type == CallType.missed)).length;
  int get trackedRejectedCalls => simTrackedCallLogs.where((c) => c.duration.inSeconds == 0 && !(c.type == CallType.incoming || c.type == CallType.missed)).length;
  int get trackedNeverAttendedCalls => simTrackedCallLogs.where((c) => c.duration.inSeconds == 0).length;
  int get trackedUniqueCalls => simTrackedCallLogs
      .map((c) => c.phoneNumber.replaceAll(RegExp(r'[^0-9]'), ''))
      .where((p) => p.length >= 8)
      .map((p) => p.length > 10 ? p.substring(p.length - 10) : p)
      .toSet()
      .length;

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

    // 2. Merge call logs without overriding user-set statuses. Call-log leads are local only
    //    (id prefix "local_") and never sent to the server's lead endpoints.
    for (var call in _callLogs) {
      if (call.phoneNumber.isNotEmpty) {
        final phone = call.phoneNumber;
        final existingKey = uniqueClients.keys.firstWhere(
          (k) => k == phone || samePhone(k, phone),
          orElse: () => '',
        );
        if (existingKey.isEmpty) {
          LeadStatus status = LeadStatus.other;
          if (_leadStatusOverrides.containsKey(phone)) {
            final stName = _leadStatusOverrides[phone]!;
            status = LeadStatus.values.firstWhere((e) => e.name == stName, orElse: () => LeadStatus.other);
          } else if (call.type == CallType.missed || call.type == CallType.rejected) {
            status = LeadStatus.followUp;
          }

          uniqueClients[phone] = LeadModel(
            id: 'local_${call.id}',
            name: call.contactName,
            phone: phone,
            status: status,
            attempts: 1,
            dateAdded: call.timestamp,
            lastCallDate: call.timestamp,
            note: _leadNotes[phone] ?? call.note ?? '',
            assignedTo: _callerName,
            assignedCallerId: _currentUserId,
          );
        } else {
          final existing = uniqueClients[existingKey]!;
          if (call.contactName != 'Unknown' && call.contactName.isNotEmpty && (existing.name == 'Unknown' || existing.name.isEmpty)) {
            existing.name = call.contactName;
          }
          if (_leadStatusOverrides.containsKey(existing.phone)) {
            final stName = _leadStatusOverrides[existing.phone]!;
            existing.status = LeadStatus.values.firstWhere((e) => e.name == stName, orElse: () => existing.status);
          }
          if (_leadNotes.containsKey(existing.phone)) {
            existing.note = _leadNotes[existing.phone]!;
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

  /// A lead belongs to the signed-in caller when its assignedCallerId is the user's id;
  /// leads without an id fall back to an exact (case-insensitive) name match.
  bool isLeadAssignedToMe(LeadModel l) {
    if (l.assignedCallerId.isNotEmpty) {
      return _currentUserId.isNotEmpty && l.assignedCallerId == _currentUserId;
    }
    final name = _callerName.trim().toLowerCase();
    return name.isNotEmpty && l.assignedTo.trim().toLowerCase() == name;
  }

  /// Leads a call session may dial: the caller's own, excluding closed ones.
  List<LeadModel> get callableSessionLeads {
    final base = (_currentRole == UserRole.caller || _isManagerCallerMode) ? _leads.where(isLeadAssignedToMe) : _leads;
    return base
        .where((l) =>
            l.status != LeadStatus.won &&
            l.status != LeadStatus.lost &&
            l.status != LeadStatus.notInterested &&
            !l.id.startsWith('local_') && // call-log contacts are not CRM leads
            last10Digits(l.phone).length >= 8)
        .toList();
  }

  List<LeadModel> get filteredLeads {
    var list = _leads;
    // Caller: ONLY leads assigned to this caller
    if (_currentRole == UserRole.caller || _isManagerCallerMode) {
      list = list.where(isLeadAssignedToMe).toList();
    }

    final f = _leadFilter.toUpperCase();
    if (f == 'ALL') return list;
    if (f.contains('BOOK') || f.contains('DEMO BOOK')) {
      return list.where((l) => l.status == LeadStatus.bookDemo).toList();
    }
    if (f.contains('RESCHEDULE')) {
      return list.where((l) => l.status == LeadStatus.demoReschedule).toList();
    }
    if (f.contains('DEMO DONE')) {
      return list.where((l) => l.status == LeadStatus.demoDone).toList();
    }
    if (f.contains('NEW')) {
      return list.where((l) => l.status == LeadStatus.newFollowUp || l.status == LeadStatus.newLead).toList();
    }
    if (f.contains('NOT PICK') || f.contains('NO ANSWER')) {
      return list.where((l) => l.status == LeadStatus.notPickup).toList();
    }
    if (f.contains('BUSY')) {
      return list.where((l) => l.status == LeadStatus.busyOnCall).toList();
    }
    if (f.contains('RENEWAL')) {
      return list.where((l) => l.status == LeadStatus.renewalFollowUp).toList();
    }
    if (f.contains('INTERESTED') || f.contains('WON')) {
      return list.where((l) => l.status == LeadStatus.interested || l.status == LeadStatus.won).toList();
    }
    if (f.contains('WARNED')) {
      return list.where((l) => l.status == LeadStatus.warned).toList();
    }
    if (f.contains('LOST') || f.contains('NOT INTERESTED')) {
      return list.where((l) => l.status == LeadStatus.lost || l.status == LeadStatus.notInterested).toList();
    }
    if (f.contains('FOLLOW')) {
      return list.where((l) => l.status == LeadStatus.followUp || l.status == LeadStatus.newFollowUp).toList();
    }
    return list;
  }

  static bool _isServerLeadId(String id) => id.isNotEmpty && id != 'demo' && !id.startsWith('local_');

  Future<void> updateLeadStatus(
    String leadIdOrPhone,
    LeadStatus newStatus, {
    String? phone,
    String? name,
    String? note,
    bool logAttempt = false,
    bool scheduleDefaultCallback = true,
  }) async {
    if (leadIdOrPhone == 'demo') return; // never persist a placeholder lead
    final lookupPhone = phone ?? leadIdOrPhone;

    LeadModel? targetLead;
    int idx = _leads.indexWhere((l) =>
        l.id == leadIdOrPhone ||
        l.phone == leadIdOrPhone ||
        samePhone(l.phone, lookupPhone));

    if (idx != -1) {
      targetLead = _leads[idx];
      targetLead.status = newStatus;
      if (name != null && name.isNotEmpty) targetLead.name = name;
      if (note != null && note.isNotEmpty) targetLead.note = note;
      if (logAttempt) {
        targetLead.attempts += 1;
        targetLead.lastCallDate = DateTime.now();
      }
    } else {
      if (last10Digits(lookupPhone).length < 8) return;
      // Local-only lead (not yet on the server)
      targetLead = LeadModel(
        id: 'local_${DateTime.now().millisecondsSinceEpoch}',
        name: name ?? lookupPhone,
        phone: lookupPhone,
        status: newStatus,
        attempts: logAttempt ? 1 : 0,
        dateAdded: DateTime.now(),
        lastCallDate: DateTime.now(),
        note: note ?? '',
        assignedTo: _callerName,
        assignedCallerId: _currentUserId,
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

    if (scheduleDefaultCallback &&
        (newStatus == LeadStatus.followUp || newStatus == LeadStatus.bookDemo || newStatus == LeadStatus.demoReschedule)) {
      addScheduledCallback(
        name: targetLead.name.isNotEmpty && targetLead.name != 'Unknown' ? targetLead.name : targetLead.phone,
        phone: targetLead.phone,
        scheduledTime: defaultCallbackTime(DateTime.now()),
        note: (note != null && note.isNotEmpty) ? note : 'Lead moved to ${targetLead.statusLabel}',
      );
    }

    _savePreferences();
    notifyListeners();

    // Persist to the backend CRM (PUT /admin/leads/:id). Local-only leads have no server id.
    if (_isServerLeadId(targetLead.id)) {
      final ok = await ApiService.updateLead(
        leadId: targetLead.id,
        status: newStatus,
        notes: (note != null && note.isNotEmpty) ? note : null,
        logAttempt: logAttempt,
      );
      if (ok) {
        // Server has it now: the local override is no longer needed
        _leadStatusOverrides.remove(finalPhone);
        if (note != null && note.isNotEmpty) _leadNotes.remove(finalPhone);
        _savePreferences();
      }
    }
  }

  Future<void> addLeadNote(String leadIdOrPhone, String newNote) async {
    final idx = _leads.indexWhere((l) =>
        l.id == leadIdOrPhone ||
        l.phone == leadIdOrPhone ||
        samePhone(l.phone, leadIdOrPhone));

    if (idx != -1) {
      final lead = _leads[idx];
      lead.note = newNote;
      if (lead.phone.isNotEmpty) {
        _leadNotes[lead.phone] = newNote;
      }
      _savePreferences();
      notifyListeners();

      if (_isServerLeadId(lead.id)) {
        final ok = await ApiService.updateLead(leadId: lead.id, notes: newNote);
        if (ok) {
          _leadNotes.remove(lead.phone);
          _savePreferences();
        }
      }
    }
  }

  // Scheduled Callbacks (100% Dynamic - strictly for current session & user-scheduled)
  final List<ScheduledCallback> _callbacks = [];

  List<ScheduledCallback> get callbacks => _callbacks;

  void _syncCallbacksFromCallLogs() {
    final Set<String> existingLast10 = _callbacks.map((c) => last10Digits(c.phone)).toSet();

    final sessionStart = _loginSessionTimestamp;
    if (sessionStart == null) return;

    var added = false;
    for (var call in _callLogs) {
      final last10 = last10Digits(call.phoneNumber);

      if (call.timestamp.isAfter(sessionStart) &&
          (call.type == CallType.missed || call.type == CallType.rejected) &&
          last10.isNotEmpty &&
          !existingLast10.contains(last10)) {
        _callbacks.add(
          ScheduledCallback(
            id: 'cb_${call.id}',
            name: call.contactName != 'Unknown' ? call.contactName : call.phoneNumber,
            phone: call.phoneNumber,
            scheduledTime: defaultCallbackTime(DateTime.now(), hoursAhead: 1),
            note: 'Missed call follow-up required',
          ),
        );
        existingLast10.add(last10);
        added = true;
      }
    }
    if (added) {
      _callbacks.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
      _savePreferences();
    }
  }

  void addScheduledCallback({
    required String name,
    required String phone,
    required DateTime scheduledTime,
    required String note,
  }) {
    final last10 = last10Digits(phone);

    // Remove old persisted callback record so rescheduled record does not duplicate
    _callbacks.removeWhere((c) {
      final samePhoneNumber = last10.isNotEmpty && last10Digits(c.phone) == last10;
      final sameName = name.trim().isNotEmpty && c.name.trim().toLowerCase() == name.trim().toLowerCase();
      return samePhoneNumber || sameName;
    });

    _callbacks.insert(
      0,
      ScheduledCallback(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        phone: phone,
        scheduledTime: normalizeCallbackTime(scheduledTime, DateTime.now()),
        note: note.isNotEmpty ? note : 'Follow-up call scheduled',
      ),
    );
    _callbacks.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    _savePreferences();
    notifyListeners();
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

  // ---- Playback: real position / duration polled from the native MediaPlayer
  Timer? _playbackPollTimer;
  String? _playingRecordingId;

  void _stopPlaybackPolling() {
    _playbackPollTimer?.cancel();
    _playbackPollTimer = null;
    _playingRecordingId = null;
  }

  void _onPlaybackFinished() {
    _stopPlaybackPolling();
    var changed = false;
    for (final r in _recordings) {
      if (r.isPlaying || r.progress != 0) {
        r.isPlaying = false;
        r.progress = 0;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  Future<void> toggleRecordingPlayback(String id) async {
    final target = _recordings.where((r) => r.id == id).firstOrNull;
    if (target == null) return;
    final startPlaying = !target.isPlaying;
    for (final r in _recordings) {
      r.isPlaying = false;
      r.progress = 0;
    }
    _stopPlaybackPolling();
    if (!startPlaying) {
      notifyListeners();
      await _telephonyChannel.invokeMethod('stopAudio').catchError((_) => null);
      return;
    }
    target.isPlaying = true;
    notifyListeners();
    bool started = false;
    try {
      started = await _telephonyChannel.invokeMethod<bool>('playAudio', {
            'filePath': target.filePath,
            'audioUrl': ApiService.authorizedMediaUrl(target.audioUrl),
            'audioData': target.audioData ?? '',
          }) ??
          false;
    } catch (e) {
      debugPrint('playAudio error: $e');
    }
    if (!started) {
      target.isPlaying = false;
      notifyListeners();
      return;
    }
    _playingRecordingId = id;
    _playbackPollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _pollPlaybackPosition());
  }

  Future<void> _pollPlaybackPosition() async {
    final id = _playingRecordingId;
    if (id == null) return;
    try {
      final res = await _telephonyChannel.invokeMethod('getPlaybackPosition');
      if (res is! Map || id != _playingRecordingId) return;
      final pos = asInt(res['position']);
      final dur = asInt(res['duration']);
      final playing = res['isPlaying'] == true;
      final rec = _recordings.where((r) => r.id == id).firstOrNull;
      if (rec == null) {
        _stopPlaybackPolling();
        return;
      }
      if (dur > 0) rec.progress = (pos / dur).clamp(0.0, 1.0);
      rec.playbackPosition = Duration(milliseconds: pos);
      if (dur > 0) rec.playbackDuration = Duration(milliseconds: dur);
      if (!playing && pos == 0 && rec.progress == 0) return; // still buffering a stream
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> deleteRecording(String id) async {
    final ok = await ApiService.deleteRecording(id);
    if (ok) {
      _recordings.removeWhere((r) => r.id == id);
      notifyListeners();
    }
    return ok;
  }

  // Direct Telephony Actions
  /// Places a call on the work SIM ([slot] is 0-based; defaults to the work SIM).
  /// Falls back to the system dialer if the native call fails.
  Future<void> makeDirectCall(String phone, {int? slot}) async {
    final clean = phone.trim();
    if (clean.isEmpty) return;
    try {
      await _telephonyChannel.invokeMethod('directCall', {
        'phoneNumber': clean,
        'slotIndex': slot ?? workSimSlotIndex,
      });
    } catch (e) {
      debugPrint('directCall failed, opening dialer: $e');
      try {
        await launchUrl(Uri.parse('tel:$clean'), mode: LaunchMode.externalApplication);
      } catch (e2) {
        debugPrint('tel: launch failed: $e2');
      }
    }
  }

  Future<void> launchCall(String phone) => makeDirectCall(phone);

  Future<void> launchWhatsApp(String phone, {String text = 'Hello from BDE team!'}) async {
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

  Future<void> launchSms(String phone, {String text = 'Hello from BDE team! Please call us back.'}) async {
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

  Future<void> launchSMS(String phone, {String text = 'Hello from BDE team! Please call us back.'}) => launchSms(phone, text: text);

  // Report export is not available on the device; the web portal has it.
  static const String exportUnavailableMessage = 'Export is available on the web portal.';

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

    // 1. Immediately store in CRM contacts map
    _crmContactNames[last10] = name;

    // 2. Immediately update matching leads
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

    // 3. Immediately update matching call logs in-memory
    for (int i = 0; i < _callLogs.length; i++) {
      final c = _callLogs[i];
      if (c.phoneNumber.replaceAll(RegExp(r'[^0-9]'), '').endsWith(last10)) {
        _callLogs[i] = CallLogModel(
          id: c.id,
          contactName: name,
          phoneNumber: c.phoneNumber,
          type: c.type,
          duration: c.duration,
          timestamp: c.timestamp,
          simSlot: c.simSlot,
          note: notes ?? c.note,
          recordingPath: c.recordingPath,
          agentName: c.agentName,
          isCrmContact: true,
        );
      }
    }

    _savePreferences();
    notifyListeners();

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
    return true;
  }

  Future<Map<String, dynamic>> createUser({
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
  // Duty starts at login (or when the user toggles ON DUTY) and is persisted; null = not started.
  bool _isOnDuty = false;
  bool get isOnDuty => _isOnDuty;
  DateTime? _dutyStartTime;
  DateTime? get dutyStartTime => _dutyStartTime;

  bool _isOnBreak = false;
  bool get isOnBreak => _isOnBreak;
  String _currentBreakType = '';
  String get currentBreakType => _currentBreakType;
  DateTime? _breakStartTime;

  final List<Map<String, dynamic>> _breakLogs = [];
  List<Map<String, dynamic>> get breakLogs => _breakLogs;
  int get totalBreakMinutes => _breakLogs.fold(0, (sum, b) => sum + asInt(b['mins']));

  void toggleDuty() {
    _isOnDuty = !_isOnDuty;
    if (_isOnDuty) {
      _dutyStartTime = DateTime.now();
    } else {
      _dutyStartTime = null;
      if (_isOnBreak) endBreak();
    }
    _isOnBreak = false;
    _savePreferences();
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

  /// When the current session call was dialed / closed (for the outcome screen).
  DateTime? _sessionCallStartedAt;
  DateTime? get sessionCallStartedAt => _sessionCallStartedAt;
  DateTime? _sessionCallEndedAt;
  DateTime? get sessionCallEndedAt => _sessionCallEndedAt;

  Timer? _sessionCallTimer;

  void _startSessionTimer() {
    _sessionCallTimer?.cancel();
    _callTimerSeconds = 0;
    _sessionCallStartedAt = DateTime.now();
    _sessionCallEndedAt = null;
    _sessionCallTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _callTimerSeconds++;
      notifyListeners();
    });
  }

  /// Starts a dialing session over [leads] (default: the caller's own open leads).
  /// Does nothing (activeCallLead stays null) when there is no lead to call.
  void startCallSession({List<LeadModel>? leads, int startIndex = 0}) {
    final available = (leads ?? callableSessionLeads).where((l) => l.id != 'demo' && l.phone.trim().isNotEmpty).toList();
    if (available.isEmpty) {
      _sessionQueue = [];
      _activeCallLead = null;
      notifyListeners();
      return;
    }
    _sessionQueue = available;
    _sessionIndex = startIndex.clamp(0, _sessionQueue.length - 1);
    _activeCallLead = _sessionQueue[_sessionIndex];
    _startSessionTimer();
    makeDirectCall(_activeCallLead!.phone);
    notifyListeners();
  }

  /// Stops the on-screen call timer (called when the call screen closes).
  /// [notify] must be false when called from a widget's dispose().
  void endSessionCall({bool notify = true}) {
    final wasRunning = _sessionCallTimer != null;
    _sessionCallTimer?.cancel();
    _sessionCallTimer = null;
    if (wasRunning) {
      _sessionCallEndedAt = DateTime.now();
      if (notify) notifyListeners();
    }
  }

  /// Dials the current session lead (user tapped CALL) and restarts the on-screen timer.
  void dialActiveLead() {
    final lead = _activeCallLead;
    if (lead == null) return;
    _startSessionTimer();
    makeDirectCall(lead.phone);
    notifyListeners();
  }

  bool get isSessionTimerRunning => _sessionCallTimer != null;

  /// Most recent device call with [phone] at or after [since] (1 min tolerance), or null.
  CallLogModel? latestDeviceCallFor(String phone, {DateTime? since}) {
    CallLogModel? best;
    for (final c in _callLogs) {
      if (!samePhone(c.phoneNumber, phone)) continue;
      if (since != null && c.timestamp.isBefore(since.subtract(const Duration(minutes: 1)))) continue;
      if (best == null || c.timestamp.isAfter(best.timestamp)) best = c;
    }
    return best;
  }

  LeadModel? get nextSessionLead {
    if (_sessionIndex + 1 < _sessionQueue.length) {
      return _sessionQueue[_sessionIndex + 1];
    }
    return null;
  }

  int get remainingSessionCount => (_sessionQueue.length - _sessionIndex - 1).clamp(0, 999);

  /// Moves to the next lead in the queue and dials it (only ever called from a user action).
  /// Returns false when the queue is finished.
  bool advanceSession() {
    if (_sessionIndex + 1 < _sessionQueue.length) {
      _sessionIndex++;
      _activeCallLead = _sessionQueue[_sessionIndex];
      _startSessionTimer();
      makeDirectCall(_activeCallLead!.phone);
      notifyListeners();
      return true;
    }
    _activeCallLead = null;
    _sessionCallTimer?.cancel();
    _sessionCallTimer = null;
    notifyListeners();
    return false;
  }

  /// Skips the current lead without saving anything. Does not dial.
  void skipSessionLead() {
    if (_sessionIndex + 1 < _sessionQueue.length) {
      _sessionIndex++;
      _activeCallLead = _sessionQueue[_sessionIndex];
    } else {
      _activeCallLead = null;
    }
    _sessionCallTimer?.cancel();
    _sessionCallTimer = null;
    notifyListeners();
  }

  /// Saves the outcome of the current call. [callbackTime] is optional (null = no callback).
  /// When [dialNext] is true the next lead is dialed; the caller UI only passes it on a button tap.
  Future<void> saveCallOutcomeAndNext({
    required LeadStatus status,
    String? note,
    bool sendBrochure = false,
    DateTime? callbackTime,
    bool takeBreak = false,
    bool dialNext = true,
  }) async {
    final currentLead = _activeCallLead;
    if (currentLead != null && currentLead.id != 'demo') {
      await updateLeadStatus(
        currentLead.id,
        status,
        phone: currentLead.phone,
        name: currentLead.name,
        note: note,
        logAttempt: true,
        scheduleDefaultCallback: false,
      );

      if (callbackTime != null) {
        addScheduledCallback(
          name: currentLead.name,
          phone: currentLead.phone,
          scheduledTime: callbackTime,
          note: (note != null && note.isNotEmpty) ? note : 'Follow-up callback',
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
      _sessionCallTimer?.cancel();
      _sessionCallTimer = null;
      notifyListeners();
      return;
    }

    if (dialNext) {
      advanceSession();
    } else {
      _activeCallLead = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sessionCallTimer?.cancel();
    _syncPollingTimer?.cancel();
    _playbackPollTimer?.cancel();
    _callLogDebounce?.cancel();
    _lifecycleListener?.dispose();
    if (ApiService.onAuthRequired == _handleAuthRequired) ApiService.onAuthRequired = null;
    super.dispose();
  }
}
