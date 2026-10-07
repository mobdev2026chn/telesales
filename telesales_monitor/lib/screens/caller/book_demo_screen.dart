import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

// Working hours 10 AM - 7 PM in 30-minute slots
const int _firstMinute = 10 * 60;
const int _lastMinute = 19 * 60;
const int _slotMinutes = 30;
const int _daysAhead = 7;

String _clock(int m) {
  final h = (m ~/ 60) % 24;
  return '${h % 12 == 0 ? 12 : h % 12}:${(m % 60).toString().padLeft(2, '0')} ${h >= 12 ? 'PM' : 'AM'}';
}

String _shortClock(int m) {
  final h = (m ~/ 60) % 12;
  return '${h == 0 ? 12 : h}:${(m % 60).toString().padLeft(2, '0')}';
}

String _range(int m) => '${_clock(m)} - ${_clock(m + _slotMinutes)}';

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// A booking or a block from GET /demos/day, as a time range on the chosen day.
class _Busy {
  final String id;
  final DateTime start;
  final int minutes;
  final bool blocked;
  final bool mine;
  final String callerName;
  final String clientName;
  final String clientPhone;
  final String course;
  final String notes;

  _Busy({
    required this.id,
    required this.start,
    required this.minutes,
    this.blocked = false,
    this.mine = false,
    this.callerName = '',
    this.clientName = '',
    this.clientPhone = '',
    this.course = '',
    this.notes = '',
  });

  DateTime get end => start.add(Duration(minutes: minutes));
  bool overlaps(DateTime s, DateTime e) => start.isBefore(e) && end.isAfter(s);

  static _Busy? fromJson(Map m, {bool blocked = false}) {
    final start = DateTime.tryParse(
      m['scheduledAt']?.toString() ?? '',
    )?.toLocal();
    if (start == null) return null;
    final minutes =
        int.tryParse(m['durationMinutes']?.toString() ?? '') ??
        (blocked ? _slotMinutes : 60);
    return _Busy(
      id: m['id']?.toString() ?? '',
      start: start,
      minutes: minutes > 0 ? minutes : 60,
      blocked: blocked,
      mine: m['mine'] == true,
      callerName: m['callerName']?.toString() ?? '',
      clientName: m['clientName']?.toString() ?? '',
      clientPhone: m['clientPhone']?.toString() ?? '',
      course: m['course']?.toString() ?? '',
      notes: m['reason']?.toString() ?? '',
    );
  }
}

/// BOOK DEMO tab: pick a team leader, a day and one or more 30-minute slots, then fill in one
/// client form for them. Booked slots show green, slots blocked from the portal red, the caller's own ★.
class BookDemoScreen extends StatefulWidget {
  const BookDemoScreen({super.key});

  @override
  State<BookDemoScreen> createState() => _BookDemoScreenState();
}

class _BookDemoScreenState extends State<BookDemoScreen> {
  late DateTime _day;
  late DateTime _dayWindowStart;
  List<Map<String, String>>? _teamLeaders; // null while loading
  String? _teamLeaderId;
  List<_Busy> _busy = [];
  bool _loadingDay = false;
  bool _offline = false;
  final Set<int> _selected = {}; // slot start minutes on _day
  List<Map<String, dynamic>> _mine = [];
  bool _loadingMine = true;
  String? _mineError;
  String? _teamLeaderError;
  Timer? _refresh;
  // A demo sent back from the portal that the caller is booking again: its details prefill the form
  // and it is closed once the new slot(s) are booked
  Map<String, dynamic>? _rebook;

  @override
  void initState() {
    super.initState();
    _day = _dayOnly(DateTime.now());
    _dayWindowStart = _day;
    _loadTeamLeaders();
    _loadMine();
    // Keep bookings and blocks from other callers and the portal fresh
    _refresh = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      _loadDay(quiet: true);
      _loadMine();
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _loadTeamLeaders() async {
    if (mounted) {
      setState(() => _teamLeaderError = null);
    }
    final list = await ApiService.fetchDemoTeamLeaders();
    if (!mounted) return;
    setState(() {
      _teamLeaders = list ?? [];
      _offline = list == null;
      _teamLeaderError = list == null
          ? '${ApiService.demoTeamLeadersError ?? 'Could not load team leaders.'} Tap to retry.'
          : null;
      if (list != null && list.length == 1) _teamLeaderId = list.first['id'];
    });
    // No team leaders on the server: bookings are made without one
    if (_teamLeaderId != null || (list != null && list.isEmpty)) _loadDay();
  }

  bool get _canPick =>
      _teamLeaderId != null || (_teamLeaders != null && _teamLeaders!.isEmpty);

  Future<void> _loadDay({bool quiet = false}) async {
    if (!_canPick) return;
    final tl = _teamLeaderId ?? '';
    final day = _day;
    if (!quiet) setState(() => _loadingDay = true);
    final data = await ApiService.fetchDemoDay(teamLeaderId: tl, day: day);
    if (!mounted || tl != (_teamLeaderId ?? '') || day != _day) return;
    setState(() {
      _loadingDay = false;
      if (data == null) {
        if (!quiet) _offline = true;
        return;
      }
      _offline = false;
      _busy = [
        ...((data['bookings'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => _Busy.fromJson(m))
            .whereType<_Busy>(),
        ...((data['blocks'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => _Busy.fromJson(m, blocked: true))
            .whereType<_Busy>(),
      ];
      // A slot someone else just took or the portal just blocked can no longer stay selected
      _selected.removeWhere((m) => _busyAt(m) != null);
    });
  }

  Future<void> _loadMine() async {
    if (mounted && _mine.isEmpty) {
      setState(() {
        _loadingMine = true;
        _mineError = null;
      });
    }
    final list = await ApiService.fetchMyDemos(
      from: DateTime.now().subtract(const Duration(minutes: 30)),
    );
    if (!mounted) return;
    if (list == null) {
      setState(() {
        _loadingMine = false;
        _mineError =
            'Could not load upcoming demos. Check your connection or sign in again, then tap to retry.';
      });
      return;
    }
    final now = DateTime.now();
    final upcoming =
        list.where((d) {
          // Sent back from the portal: stays listed until the caller books again or drops it
          if (d['status'] == 'RESCHEDULE') return true;
          if ((d['status'] ?? 'BOOKED') != 'BOOKED') return false;
          final at = DateTime.tryParse(
            d['scheduledAt']?.toString() ?? '',
          )?.toLocal();
          final mins =
              int.tryParse(d['durationMinutes']?.toString() ?? '') ?? 60;
          return at != null && at.add(Duration(minutes: mins)).isAfter(now);
        }).toList()..sort(
          (a, b) => (a['scheduledAt'] ?? '').toString().compareTo(
            (b['scheduledAt'] ?? '').toString(),
          ),
        );
    setState(() {
      _mine = upcoming;
      _loadingMine = false;
      _mineError = null;
    });
  }

  DateTime _startOf(int m) => _day.add(Duration(minutes: m));

  /// The block (first) or booking covering slot [m], if any.
  _Busy? _busyAt(int m) {
    final s = _startOf(m), e = s.add(const Duration(minutes: _slotMinutes));
    final hits = _busy.where((b) => b.overlaps(s, e)).toList();
    if (hits.isEmpty) return null;
    return hits.firstWhere((b) => b.blocked, orElse: () => hits.first);
  }

  bool _isPast(int m) => !_startOf(m).isAfter(DateTime.now());

  String get _teamLeaderName =>
      (_teamLeaders ?? const []).firstWhere(
        (t) => t['id'] == _teamLeaderId,
        orElse: () => const {'name': ''},
      )['name'] ??
      '';

  void _toast(String text) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: AppTheme.mono(
            size: 12,
            color: AppTheme.limeYellow,
            weight: FontWeight.w700,
          ),
        ),
        backgroundColor: AppTheme.ink900,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _setDay(DateTime d, {bool revealInStrip = false}) {
    setState(() {
      _day = d;
      if (revealInStrip) {
        final today = _dayOnly(DateTime.now());
        final daysFromToday = _day.difference(today).inDays;
        final startOffset = daysFromToday < 3 ? 0 : daysFromToday - 3;
        _dayWindowStart = today.add(Duration(days: startOffset));
      }
      _selected.clear();
      _busy = [];
    });
    _loadDay();
  }

  Future<void> _pickDay() async {
    final today = _dayOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.ink900,
            onPrimary: AppTheme.limeYellow,
            surface: AppTheme.paper,
            onSurface: AppTheme.ink900,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      _setDay(_dayOnly(picked), revealInStrip: true);
    }
  }

  void _setTeamLeader(String id) {
    setState(() {
      _teamLeaderId = id;
      _selected.clear();
      _busy = [];
    });
    _loadDay();
  }

  void _tap(int m) {
    final b = _busyAt(m);
    if (_isPast(m)) return _toast('Time already passed');
    if (b != null && b.blocked) return _toast('Blocked by team leader');
    if (b != null && b.mine) return _showBooking(b);
    if (b != null)
      return _toast(
        b.callerName.isNotEmpty
            ? 'Already booked by ${b.callerName}'
            : 'Already booked',
      );
    setState(
      () => _selected.contains(m) ? _selected.remove(m) : _selected.add(m),
    );
  }

  // ------------------------------------------------------------------ Booking form

  Future<void> _openForm() async {
    if (_selected.isEmpty) return;
    final slots = _selected.toList()..sort();
    final booked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        side: BorderSide(color: AppTheme.ink900, width: 2),
      ),
      builder: (_) => _DemoDetailsSheet(
        day: _day,
        slots: slots,
        teamLeaderId: _teamLeaderId ?? '',
        teamLeaderName: _teamLeaderName,
        prefill: _rebook,
      ),
    );
    if (!mounted || booked == null) return;
    setState(() => _selected.clear());
    final rebook = _rebook;
    if (booked > 0 && rebook != null) {
      // The new booking replaces the demo sent back for rescheduling
      await ApiService.cancelDemo((rebook['id'] ?? '').toString());
      if (!mounted) return;
      setState(() => _rebook = null);
    }
    if (booked > 0) _toast('$booked slot${booked > 1 ? 's' : ''} booked ✓');
    _loadDay(quiet: true);
    _loadMine();
  }

  /// BOOK AGAIN on a demo sent back from the portal: same team leader, its day (or today if it
  /// has passed), and its client details prefilled in the form once new slot(s) are picked.
  void _startRebook(Map<String, dynamic> d) {
    final tlId = (d['teamLeaderId'] ?? '').toString();
    final at = DateTime.tryParse(d['scheduledAt']?.toString() ?? '')?.toLocal();
    final today = _dayOnly(DateTime.now());
    final day = at == null || _dayOnly(at).isBefore(today) ? today : _dayOnly(at);
    setState(() {
      _rebook = d;
      if (tlId.isNotEmpty && (_teamLeaders ?? const []).any((t) => t['id'] == tlId)) {
        _teamLeaderId = tlId;
      }
    });
    _setDay(day, revealInStrip: true);
    _toast('Pick new slot(s) above, then BOOK DEMO →');
  }

  Future<void> _cancel(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppTheme.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppTheme.ink900, width: 2),
        ),
        title: Text(
          'CANCEL THIS DEMO SLOT?',
          style: AppTheme.headline(size: 20),
        ),
        content: Text(
          'The slot becomes free for other callers.',
          style: AppTheme.body(size: 13, color: AppTheme.ink700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(
              'KEEP',
              style: AppTheme.mono(size: 12, weight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(
              'CANCEL SLOT',
              style: AppTheme.mono(
                size: 12,
                color: AppTheme.redMissed,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await ApiService.cancelDemo(id);
    if (!mounted) return;
    if (err == null && _rebook != null && _rebook!['id'] == id) {
      setState(() => _rebook = null);
    }
    _toast(err ?? 'Slot released');
    _loadDay(quiet: true);
    _loadMine();
  }

  void _showBooking(_Busy b) {
    final m = b.start.hour * 60 + b.start.minute;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        side: BorderSide(color: AppTheme.ink900, width: 2),
      ),
      builder: (c) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                b.clientName.isEmpty ? 'YOUR DEMO' : b.clientName.toUpperCase(),
                style: AppTheme.headline(size: 26),
              ),
              const SizedBox(height: 4),
              Text(
                '${_clock(m)} - ${_clock(m + b.minutes)}'.toUpperCase(),
                style: _subStyle,
              ),
              _ReadOnlyField(label: 'PHONE', value: b.clientPhone),
              _ReadOnlyField(label: 'ABOUT', value: b.course),
              _ReadOnlyField(label: 'NOTES', value: b.notes),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _Btn(
                      label: 'CLOSE',
                      color: AppTheme.white,
                      onTap: () => Navigator.pop(c),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Btn(
                      label: 'CANCEL SLOT',
                      color: AppTheme.redMissed,
                      textColor: AppTheme.white,
                      onTap: () {
                        Navigator.pop(c);
                        _cancel(b.id);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          color: AppTheme.ink900,
          onRefresh: () async {
            if (_teamLeaders == null || _teamLeaders!.isEmpty)
              await _loadTeamLeaders();
            await Future.wait([_loadDay(quiet: true), _loadMine()]);
          },
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              _selected.isEmpty ? 24 : 110,
            ),
            children: [
              Text(
                'ASKEVA · TELESALES',
                style: AppTheme.mono(
                  size: 10,
                  color: AppTheme.muted,
                  weight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text('BOOK DEMO.', style: AppTheme.headline(size: 32)),
              const SizedBox(height: 14),
              if (_teamLeaders == null || _teamLeaders!.isNotEmpty)
                _teamLeaderCard(),
              if (_teamLeaderError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GestureDetector(
                    onTap: _loadTeamLeaders,
                    child: Text(
                      '${_teamLeaderError!} You can still book without a team leader.',
                      style: AppTheme.body(size: 11, color: AppTheme.redMissed),
                    ),
                  ),
                ),
              _card(
                label: '${_stepNo(2)} · PICK DATE',
                trailing: IconButton(
                  tooltip: 'Choose date',
                  onPressed: _pickDay,
                  icon: const Icon(Icons.calendar_month_rounded),
                  color: AppTheme.ink900,
                  constraints: const BoxConstraints.tightFor(
                    width: 34,
                    height: 34,
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                child: _daysRow(),
              ),
              _card(
                label: '${_stepNo(3)} · PICK SLOT(S) — 10:00 AM TO 7:00 PM',
                child: _slotsBody(),
              ),
              _card(label: 'MY UPCOMING DEMOS', child: _mineBody()),
            ],
          ),
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: _selectionBar()),
      ],
    );
  }

  // Steps renumber when there is no team leader to choose
  String _stepNo(int n) =>
      (_teamLeaders != null && _teamLeaders!.isEmpty) ? '${n - 1}' : '$n';

  static final TextStyle _subStyle = AppTheme.mono(
    size: 10,
    color: AppTheme.muted,
    weight: FontWeight.w400,
  );

  Widget _card({
    required String label,
    Widget? trailing,
    required Widget child,
  }) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppTheme.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppTheme.ink900, width: 2),
      boxShadow: AppTheme.neoShadowSm(),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTheme.mono(
                  size: 10,
                  color: AppTheme.muted,
                  weight: FontWeight.w400,
                ).copyWith(letterSpacing: 1.5),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );

  Widget _chip({
    required Widget child,
    required bool on,
    required VoidCallback onTap,
    EdgeInsets? padding,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: on ? AppTheme.ink900 : const Color(0xFFF4F4F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.ink900, width: 2),
      ),
      child: DefaultTextStyle.merge(
        style: AppTheme.mono(
          size: 11,
          color: on ? AppTheme.limeYellow : AppTheme.ink900,
          weight: FontWeight.w700,
        ),
        child: child,
      ),
    ),
  );

  Widget _teamLeaderCard() {
    Widget body;
    if (_teamLeaders == null) {
      body = Text(
        'Loading team leaders…',
        style: AppTheme.body(size: 12, color: AppTheme.muted),
      );
    } else if (_offline && _teamLeaders!.isEmpty) {
      body = GestureDetector(
        onTap: _loadTeamLeaders,
        child: Text(
          _teamLeaderError ?? 'Could not load team leaders. Tap to retry.',
          style: AppTheme.body(size: 12, color: AppTheme.redMissed),
        ),
      );
    } else {
      body = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _teamLeaders!
            .map(
              (t) => _chip(
                on: t['id'] == _teamLeaderId,
                onTap: () => _setTeamLeader(t['id']!),
                child: Text(
                  (t['name'] ?? '').isEmpty ? '—' : t['name']!.toUpperCase(),
                ),
              ),
            )
            .toList(),
      );
    }
    return _card(label: '1 · TEAM LEADER', child: body);
  }

  Widget _daysRow() {
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _daysAhead,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final d = _dayWindowStart.add(Duration(days: i));
          final on = d == _day;
          return _chip(
            on: on,
            onTap: () => _setDay(d),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: SizedBox(
              width: 42,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('EEE').format(d).toUpperCase(),
                    style: const TextStyle(fontSize: 9),
                  ),
                  Text(
                    '${d.day}',
                    style: AppTheme.headline(
                      size: 22,
                      color: on ? AppTheme.limeYellow : AppTheme.ink900,
                    ),
                  ),
                  Text(
                    DateFormat('MMM').format(d).toUpperCase(),
                    style: const TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _legendDot(Color c, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.ink900, width: 2),
        ),
      ),
      const SizedBox(width: 4),
      Text(label, style: AppTheme.mono(size: 10, weight: FontWeight.w400)),
    ],
  );

  Widget _slotsBody() {
    if (!_canPick) {
      return Text(
        _teamLeaders == null
            ? 'Loading…'
            : 'Choose a team leader to see their free slots.',
        style: AppTheme.body(size: 12, color: AppTheme.muted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            _legendDot(AppTheme.white, 'Free'),
            _legendDot(AppTheme.limeYellow, 'Selected'),
            _legendDot(AppTheme.greenNeon, 'Booked'),
            _legendDot(AppTheme.redMissed, 'Blocked'),
            Text(
              '★ Yours',
              style: AppTheme.mono(size: 10, weight: FontWeight.w400),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_loadingDay)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: AppTheme.greenNeon,
              backgroundColor: AppTheme.paper,
            ),
          ),
        if (_offline && !_loadingDay)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Offline: booked and blocked slots may be out of date.',
              style: AppTheme.body(size: 11, color: AppTheme.redMissed),
            ),
          ),
        for (int m = _firstMinute; m < _lastMinute; m += 60)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${(m ~/ 60) % 12 == 0 ? 12 : (m ~/ 60) % 12}',
                        style: AppTheme.headline(size: 15),
                      ),
                      Text(
                        m >= 12 * 60 ? 'PM' : 'AM',
                        style: AppTheme.mono(
                          size: 9,
                          color: AppTheme.muted,
                          weight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _slot(m)),
                const SizedBox(width: 8),
                Expanded(child: _slot(m + 30)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _slot(int m) {
    final b = _busyAt(m);
    final past = _isPast(m);
    final sel = _selected.contains(m);
    Color bg = AppTheme.white, fg = AppTheme.ink900;
    String mark = '';
    if (b != null && b.blocked) {
      bg = AppTheme.redMissed;
      fg = AppTheme.white;
      mark = '✕';
    } else if (b != null) {
      bg = AppTheme.greenNeon;
      fg = AppTheme.white;
      mark = b.mine ? '★' : '✓';
    } else if (sel) {
      bg = AppTheme.limeYellow;
      mark = '●';
    }
    return Opacity(
      opacity: past ? 0.35 : 1,
      child: GestureDetector(
        onTap: () => _tap(m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.ink900, width: 2),
            boxShadow: past
                ? null
                : const [
                    BoxShadow(color: AppTheme.ink900, offset: Offset(2, 2)),
                  ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Text(
                  '${_shortClock(m)}–${_shortClock(m + _slotMinutes)}${mark.isEmpty ? '' : ' $mark'}',
                  key: ValueKey('$mark$fg'),
                  style: AppTheme.mono(
                    size: 11,
                    color: fg,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mineBody() {
    if (_mine.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: GestureDetector(
          onTap: _mineError == null ? null : _loadMine,
          child: Text(
            _loadingMine
                ? 'Loading upcoming demos…'
                : (_mineError ?? 'No demos booked yet.'),
            style: AppTheme.mono(
              size: 12,
              color: _mineError == null ? AppTheme.muted : AppTheme.redMissed,
              weight: FontWeight.w400,
            ),
          ),
        ),
      );
    }
    return Column(
      children: [
        if (_mineError != null)
          GestureDetector(
            onTap: _loadMine,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _mineError!,
                style: AppTheme.body(size: 11, color: AppTheme.redMissed),
              ),
            ),
          ),
        ..._mine.map((d) {
          final at = DateTime.tryParse(
            d['scheduledAt']?.toString() ?? '',
          )?.toLocal();
          final mins =
              int.tryParse(d['durationMinutes']?.toString() ?? '') ?? 60;
          final m = at == null ? 0 : at.hour * 60 + at.minute;
          final tl = (d['teamLeaderName'] ?? '').toString();
          final client = (d['clientName'] ?? '').toString();
          final resched = d['status'] == 'RESCHEDULE';
          final rebooking = _rebook != null && _rebook!['id'] == d['id'];
          return AnimatedContainer(
            key: ValueKey(d['id']),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: resched ? const Color(0xFFFFF3E0) : const Color(0xFFF4FFF0),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: resched ? AppTheme.redMissed : AppTheme.ink900,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (resched)
                        Text(
                          rebooking
                              ? 'RESCHEDULE · PICK NEW SLOT(S) ABOVE'
                              : 'RESCHEDULE NEEDED · BOOK AGAIN',
                          style: AppTheme.mono(
                            size: 10,
                            color: AppTheme.redMissed,
                            weight: FontWeight.w700,
                          ),
                        ),
                      Text(
                        '${_clock(m)} - ${_clock(m + mins)}',
                        style: AppTheme.headline(size: 17).copyWith(
                          decoration: resched ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (at != null) DateFormat('d MMM').format(at),
                          client,
                          if (tl.isNotEmpty) 'with $tl',
                        ].where((s) => s.isNotEmpty).join(' · '),
                        style: AppTheme.mono(
                          size: 11,
                          color: AppTheme.ink700,
                          weight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                if (resched)
                  _Btn(
                    label: rebooking ? 'PICKING…' : 'BOOK AGAIN',
                    color: AppTheme.limeYellow,
                    onTap: () => _startRebook(d),
                  )
                else
                  IconButton(
                    tooltip: 'Add to Google Calendar',
                    onPressed: () => _addToGoogleCalendar(d),
                    icon: const Icon(Icons.event_available_rounded),
                    color: AppTheme.ink900,
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _cancel((d['id'] ?? '').toString()),
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.ink900, width: 2),
                    ),
                    child: Text(
                      '✕',
                      style: AppTheme.mono(size: 13, weight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Future<void> _addToGoogleCalendar(Map<String, dynamic> demo) async {
    final start = DateTime.tryParse(
      demo['scheduledAt']?.toString() ?? '',
    )?.toLocal();
    if (start == null) {
      _toast('This booking has no valid date and time.');
      return;
    }
    final durationMinutes =
        int.tryParse(demo['durationMinutes']?.toString() ?? '') ?? 60;
    final end = start.add(Duration(minutes: durationMinutes));
    final clientName = (demo['clientName'] ?? 'Client').toString();
    final details = [
      'Client: $clientName',
      if ((demo['clientPhone'] ?? '').toString().isNotEmpty)
        'Phone: ${demo['clientPhone']}',
      if ((demo['course'] ?? '').toString().isNotEmpty)
        'Course: ${demo['course']}',
      if ((demo['teamLeaderName'] ?? '').toString().isNotEmpty)
        'Team leader: ${demo['teamLeaderName']}',
      if ((demo['reason'] ?? '').toString().isNotEmpty)
        'Notes: ${demo['reason']}',
    ].join('\n');
    final uri = Uri.https('calendar.google.com', '/calendar/render', {
      'action': 'TEMPLATE',
      'text': 'Demo with $clientName',
      'dates':
          '${DateFormat("yyyyMMdd'T'HHmmss'Z'").format(start.toUtc())}/${DateFormat("yyyyMMdd'T'HHmmss'Z'").format(end.toUtc())}',
      'details': details,
    });
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) _toast('Could not open Google Calendar.');
  }

  Widget _selectionBar() {
    final n = _selected.length;
    return AnimatedSlide(
      offset: n > 0 ? Offset.zero : const Offset(0, 1.2),
      duration: const Duration(milliseconds: 200),
      child: Container(
        color: AppTheme.ink900,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SELECTED',
                    style: AppTheme.mono(
                      size: 10,
                      color: AppTheme.white,
                      weight: FontWeight.w400,
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$n',
                        style: AppTheme.headline(
                          size: 22,
                          color: AppTheme.limeYellow,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        n == 1 ? 'slot' : 'slots',
                        style: AppTheme.mono(
                          size: 11,
                          color: AppTheme.white,
                          weight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _Btn(
              label: 'CLEAR',
              color: AppTheme.white,
              borderColor: AppTheme.limeYellow,
              onTap: () => setState(_selected.clear),
            ),
            const SizedBox(width: 8),
            _Btn(
              label: 'BOOK DEMO →',
              color: AppTheme.limeYellow,
              borderColor: AppTheme.limeYellow,
              onTap: _openForm,
            ),
          ],
        ),
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final Color borderColor;
  final VoidCallback? onTap;
  final bool busy;

  const _Btn({
    required this.label,
    required this.color,
    this.textColor = AppTheme.ink900,
    this.borderColor = AppTheme.ink900,
    this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: busy ? null : onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.ink900,
              ),
            )
          : Text(
              label,
              style: AppTheme.mono(
                size: 12,
                color: textColor,
                weight: FontWeight.w700,
              ),
            ),
    ),
  );
}

class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;

  const _ReadOnlyField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(
          label,
          style: AppTheme.mono(
            size: 10,
            color: AppTheme.muted,
            weight: FontWeight.w400,
          ).copyWith(letterSpacing: 1.5),
        ),
      ),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.ink900, width: 2),
        ),
        child: Text(
          value.isEmpty ? '—' : value,
          style: AppTheme.mono(size: 13, weight: FontWeight.w400),
        ),
      ),
    ],
  );
}

/// "DEMO DETAILS": one client form for all selected slots, which are listed with their times.
/// Each slot is still booked separately with the same details. Pops the number of slots booked.
class _DemoDetailsSheet extends StatefulWidget {
  final DateTime day;
  final List<int> slots;
  final String teamLeaderId;
  final String teamLeaderName;
  final Map<String, dynamic>? prefill; // demo being booked again after a reschedule request

  const _DemoDetailsSheet({
    required this.day,
    required this.slots,
    required this.teamLeaderId,
    required this.teamLeaderName,
    this.prefill,
  });

  @override
  State<_DemoDetailsSheet> createState() => _DemoDetailsSheetState();
}

class _DemoDetailsSheetState extends State<_DemoDetailsSheet> {
  late final _client = TextEditingController(text: _pre('clientName'));
  late final _phone = TextEditingController(
    text: _pre('clientPhone').replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^91(?=\d{10}$)'), ''),
  );
  late final _about = TextEditingController(text: _pre('course'));
  late final _notes = TextEditingController(text: _pre('reason'));

  String _pre(String key) => (widget.prefill?[key] ?? '').toString();
  final Set<int> _done = {}; // indexes into widget.slots already booked
  bool _saving = false;
  String? _error;
  int _booked = 0;

  @override
  void dispose() {
    _client.dispose();
    _phone.dispose();
    _about.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_client.text.trim().isEmpty)
      return setState(() => _error = 'Enter client name');
    if (!RegExp(r'^\d{10}$').hasMatch(_phone.text.trim()))
      return setState(() => _error = 'Enter valid 10-digit phone');
    if (_about.text.trim().isEmpty)
      return setState(() => _error = 'Enter client need');
    setState(() {
      _saving = true;
      _error = null;
    });
    final failures = <String>[];
    for (int i = 0; i < widget.slots.length; i++) {
      if (_done.contains(i)) continue;
      final m = widget.slots[i];
      final start = widget.day.add(Duration(minutes: m));
      if (!start.isAfter(DateTime.now())) {
        failures.add('${_range(m)}: time already passed');
        continue;
      }
      final err = await ApiService.bookDemo(
        leadId: '',
        clientName: _client.text.trim(),
        clientPhone: _phone.text.trim(),
        scheduledAt: start,
        slot: _range(m),
        course: _about.text.trim(),
        reason: _notes.text.trim(),
        teamLeaderId: widget.teamLeaderId,
        durationMinutes: _slotMinutes,
      );
      if (!mounted) return;
      if (err == null) {
        _done.add(i);
        _booked++;
      } else {
        failures.add('${_range(m)}: $err');
      }
    }
    if (!mounted) return;
    if (failures.isEmpty) {
      Navigator.of(context).pop(_booked);
      return;
    }
    setState(() {
      _saving = false;
      _error =
          '${_booked > 0 ? '$_booked booked. ' : ''}Not booked:\n${failures.join('\n')}';
    });
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Text(
      t,
      style: AppTheme.mono(
        size: 10,
        color: AppTheme.muted,
        weight: FontWeight.w400,
      ).copyWith(letterSpacing: 1.5),
    ),
  );

  Widget _field(
    TextEditingController c,
    String hint, {
    bool phone = false,
    int lines = 1,
    bool enabled = true,
  }) => TextField(
    controller: c,
    enabled: enabled,
    maxLines: lines,
    minLines: lines,
    keyboardType: phone
        ? TextInputType.number
        : (lines > 1 ? TextInputType.multiline : TextInputType.text),
    inputFormatters: phone
        ? [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ]
        : null,
    textCapitalization: phone
        ? TextCapitalization.none
        : TextCapitalization.sentences,
    style: AppTheme.mono(size: 13, weight: FontWeight.w400),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: AppTheme.mono(
        size: 13,
        color: AppTheme.muted,
        weight: FontWeight.w400,
      ),
      isDense: true,
      filled: true,
      fillColor: AppTheme.white,
      contentPadding: const EdgeInsets.all(11),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.ink900, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.lightMuted, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.greenDark, width: 2),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final n = widget.slots.length;
    final sub = [
      DateFormat('EEEE, d MMMM').format(widget.day),
      if (widget.teamLeaderName.isNotEmpty) 'with ${widget.teamLeaderName}',
    ].join(' · ').toUpperCase();
    final allDone = _done.length == n;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DEMO DETAILS', style: AppTheme.headline(size: 26)),
                const SizedBox(height: 4),
                Text(
                  sub,
                  style: AppTheme.mono(
                    size: 10,
                    color: AppTheme.muted,
                    weight: FontWeight.w400,
                  ).copyWith(letterSpacing: 1.5),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppTheme.ink900, width: 2),
                    boxShadow: AppTheme.neoShadowSm(),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label(n > 1 ? 'SELECTED TIMES ($n SLOTS)' : 'SELECTED TIME'),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (int i = 0; i < n; i++)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: _done.contains(i)
                                    ? AppTheme.greenNeon
                                    : AppTheme.limeYellow,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: AppTheme.ink900,
                                  width: 2,
                                ),
                              ),
                              child: Text(
                                '${_range(widget.slots[i])}${_done.contains(i) ? ' · BOOKED ✓' : ''}',
                                style: AppTheme.mono(
                                  size: 11,
                                  weight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      _label('CLIENT NAME'),
                      _field(_client, 'Client name', enabled: !allDone),
                      _label('CLIENT PHONE'),
                      _field(
                        _phone,
                        '10-digit number',
                        phone: true,
                        enabled: !allDone,
                      ),
                      _label('ABOUT / CLIENT NEED'),
                      _field(
                        _about,
                        'e.g. Full-stack course, weekend batch',
                        enabled: !allDone,
                      ),
                      _label('NOTES'),
                      _field(
                        _notes,
                        'Anything to know before the demo',
                        lines: 3,
                        enabled: !allDone,
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: AppTheme.bodyBold(
                      size: 12,
                      color: AppTheme.redMissed,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _Btn(
                        label: _booked > 0 ? 'DONE' : 'CANCEL',
                        color: AppTheme.white,
                        onTap: _saving
                            ? null
                            : () => Navigator.of(context).pop(_booked),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Btn(
                        label: n > 1 ? 'CONFIRM $n SLOTS' : 'CONFIRM BOOKING',
                        color: AppTheme.limeYellow,
                        busy: _saving,
                        onTap: _confirm,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
