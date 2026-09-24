import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/lead_model.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Demo booking after a call: pick an hourly slot, then fill in the "BOOK DEMO SLOT" form.
/// Returns the booked slot start when the demo was saved on the server, null when closed.
/// [onBooked] receives the client name as saved.
Future<DateTime?> showBookDemoSheet(
  BuildContext context, {
  required LeadModel lead,
  required String agentName,
  ValueChanged<String>? onBooked,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.paper,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => BookDemoSheet(lead: lead, agentName: agentName, onBooked: onBooked),
  );
}

// Working hours 10 AM - 7 PM, one-hour slots
const int _firstHour = 10;
const int _lastHour = 19;
const int _slotMinutes = 60;

String _fmtTime(DateTime d) => DateFormat('h:mm a').format(d).toUpperCase();
String _slotLabel(DateTime start) => '${_fmtTime(start)} - ${_fmtTime(start.add(const Duration(minutes: _slotMinutes)))}';

/// Small green square used before the section titles ("■ BOOK DEMO SLOT").
Widget _titleRow(String text, {double size = 13}) => Row(
      children: [
        Container(width: 10, height: 10, color: AppTheme.greenNeon),
        const SizedBox(width: 8),
        Flexible(child: Text(text, style: AppTheme.mono(size: size, color: AppTheme.ink900, weight: FontWeight.w700))),
      ],
    );

class BookDemoSheet extends StatefulWidget {
  final LeadModel lead;
  final String agentName;
  final ValueChanged<String>? onBooked;

  const BookDemoSheet({super.key, required this.lead, required this.agentName, this.onBooked});

  @override
  State<BookDemoSheet> createState() => _BookDemoSheetState();
}

class _BookDemoSheetState extends State<BookDemoSheet> {
  late DateTime _date;
  // Team Leader who runs the demo (the booking shows in their portal)
  List<Map<String, String>>? _teamLeaders; // null while loading
  bool _teamLeadersFailed = false; // offline / older server: book without a Team Leader
  String? _teamLeaderId;
  Set<int> _bookedStarts = {}; // slot starts (ms) already booked for that Team Leader on _date
  bool _loadingSlots = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Today while a slot is still open, otherwise tomorrow
    _date = _slotStarts(today).any((s) => s.isAfter(now)) ? today : today.add(const Duration(days: 1));
    _loadTeamLeaders();
  }

  Future<void> _loadTeamLeaders() async {
    final list = await ApiService.fetchDemoTeamLeaders();
    if (!mounted) return;
    setState(() {
      _teamLeaders = list ?? [];
      _teamLeadersFailed = list == null || list.isEmpty;
      if (list != null && list.length == 1) _teamLeaderId = list.first['id'];
    });
    if (_teamLeaderId != null) _loadBookedSlots();
  }

  Future<void> _loadBookedSlots() async {
    final tlId = _teamLeaderId;
    if (tlId == null) return;
    final day = _date;
    setState(() => _loadingSlots = true);
    final booked = await ApiService.fetchBookedDemoSlots(teamLeaderId: tlId, day: day);
    if (!mounted || tlId != _teamLeaderId || day != _date) return;
    setState(() {
      _bookedStarts = (booked ?? {}).map((d) => d.millisecondsSinceEpoch).toSet();
      _loadingSlots = false;
    });
  }

  String get _teamLeaderName =>
      (_teamLeaders ?? const []).firstWhere((t) => t['id'] == _teamLeaderId, orElse: () => const {'name': ''})['name'] ?? '';

  /// Slots can be picked once a Team Leader is chosen (or when none can be loaded).
  bool get _canPickSlots => _teamLeaderId != null || _teamLeadersFailed;

  List<DateTime> _slotStarts(DateTime day) => [
        for (int h = _firstHour; h < _lastHour; h++) DateTime(day.year, day.month, day.day, h),
      ];

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 60)),
      builder: (c, child) => Theme(
        data: Theme.of(c).copyWith(
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
      setState(() {
        _date = picked;
        _bookedStarts = {};
      });
      _loadBookedSlots();
    }
  }

  Future<void> _book(DateTime start) async {
    final booked = await showDialog<DateTime>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BookSlotDialog(
        lead: widget.lead,
        agentName: widget.agentName,
        start: start,
        teamLeaderId: _teamLeaderId ?? '',
        teamLeaderName: _teamLeaderName,
        onBooked: widget.onBooked,
      ),
    );
    if (booked != null && mounted) {
      Navigator.of(context).pop(booked);
    } else if (mounted) {
      _loadBookedSlots(); // someone else may have taken the slot meanwhile
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final who = widget.lead.name.trim().isNotEmpty && widget.lead.name.toLowerCase() != 'unknown'
        ? widget.lead.name.trim()
        : widget.lead.phone;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppTheme.muted, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            _titleRow('BOOK DEMO SLOT', size: 14),
            const SizedBox(height: 4),
            Text('Pick a slot for ${who.isEmpty ? 'this client' : who}', style: AppTheme.mono(size: 11, color: AppTheme.ink700)),
            const SizedBox(height: 14),

            // Team Leader who runs the demo
            Text('TEAM LEADER', style: AppTheme.mono(size: 9.5, color: AppTheme.ink900, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (_teamLeaders == null)
              Text('Loading team leaders…', style: AppTheme.body(size: 12, color: AppTheme.muted))
            else if (_teamLeadersFailed)
              Text('No team leaders found. The demo will be booked without one.', style: AppTheme.body(size: 12, color: AppTheme.muted))
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.ink900, width: 1.5),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _teamLeaderId,
                    isExpanded: true,
                    hint: Text('Select a team leader', style: AppTheme.body(size: 13, color: AppTheme.muted)),
                    icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.ink900),
                    style: AppTheme.bodyBold(size: 13, color: AppTheme.ink900),
                    items: _teamLeaders!
                        .map((t) => DropdownMenuItem(value: t['id'], child: Text(t['name']!.isEmpty ? '—' : t['name']!)))
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _teamLeaderId = v;
                        _bookedStarts = {};
                      });
                      _loadBookedSlots();
                    },
                  ),
                ),
              ),
            const SizedBox(height: 12),

            // Date
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.ink900, width: 1.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 16, color: AppTheme.ink900),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        DateFormat('EEEE, MMMM d, yyyy').format(_date),
                        style: AppTheme.mono(size: 12, color: AppTheme.ink900, weight: FontWeight.w700),
                      ),
                    ),
                    Text('CHANGE', style: AppTheme.mono(size: 10, color: AppTheme.greenDark, weight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Hourly slots
            if (!_canPickSlots && _teamLeaders != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Choose a team leader to see their free slots.', style: AppTheme.body(size: 12, color: AppTheme.muted)),
              ),
            if (_loadingSlots)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(minHeight: 2, color: AppTheme.greenNeon, backgroundColor: AppTheme.paper),
              ),
            if (_canPickSlots) ..._slotStarts(_date).map((start) {
              final passed = !start.isAfter(now);
              final taken = !passed && _bookedStarts.contains(start.millisecondsSinceEpoch);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                decoration: BoxDecoration(
                  color: passed ? AppTheme.paper : AppTheme.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: passed ? AppTheme.lightMuted : AppTheme.ink900, width: 1.2),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _slotLabel(start),
                        style: AppTheme.mono(size: 12, color: passed ? AppTheme.muted : AppTheme.ink900, weight: FontWeight.w700),
                      ),
                    ),
                    if (passed)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: Text('PASSED', style: AppTheme.mono(size: 10, color: AppTheme.muted, weight: FontWeight.w700)),
                      )
                    else if (taken)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppTheme.paper,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppTheme.lightMuted, width: 1.2),
                        ),
                        child: Text('BOOKED', style: AppTheme.mono(size: 10, color: AppTheme.muted, weight: FontWeight.w700)),
                      )
                    else
                      GestureDetector(
                        onTap: () => _book(start),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppTheme.ink900, width: 1.2),
                          ),
                          child: Text('+ BOOK', style: AppTheme.mono(size: 10.5, color: AppTheme.ink900, weight: FontWeight.w700)),
                        ),
                      ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
            Text('Pick a slot to book it. A booked slot is locked for that team leader.', style: AppTheme.body(size: 11, color: AppTheme.muted)),
          ],
        ),
      ),
    );
  }
}

/// The "BOOK DEMO SLOT" form for one slot. Pops the slot start when the demo is saved.
class _BookSlotDialog extends StatefulWidget {
  final LeadModel lead;
  final String agentName;
  final DateTime start;
  final String teamLeaderId; // '' when no team leader could be loaded
  final String teamLeaderName;
  final ValueChanged<String>? onBooked;

  const _BookSlotDialog({
    required this.lead,
    required this.agentName,
    required this.start,
    this.teamLeaderId = '',
    this.teamLeaderName = '',
    this.onBooked,
  });

  @override
  State<_BookSlotDialog> createState() => _BookSlotDialogState();
}

class _BookSlotDialogState extends State<_BookSlotDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  final TextEditingController _courseCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final name = widget.lead.name.trim();
    _nameCtrl = TextEditingController(text: name.toLowerCase() == 'unknown' ? '' : name);
    _phoneCtrl = TextEditingController(text: widget.lead.phone);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _courseCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final course = _courseCtrl.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Enter the client name.');
    if (phone.replaceAll(RegExp(r'[^0-9]'), '').length < 10) return setState(() => _error = 'Enter a valid client phone number.');
    if (course.isEmpty) return setState(() => _error = 'Enter the class / course.');
    if (!widget.start.isAfter(DateTime.now())) return setState(() => _error = 'This slot has passed. Close and pick another one.');
    setState(() {
      _saving = true;
      _error = null;
    });
    final err = await ApiService.bookDemo(
      leadId: widget.lead.id.startsWith('local_') || widget.lead.id == 'demo' ? '' : widget.lead.id,
      clientName: name,
      clientPhone: phone,
      scheduledAt: widget.start,
      slot: _slotLabel(widget.start),
      course: course,
      teamLeaderId: widget.teamLeaderId,
      reason: _notesCtrl.text.trim(),
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _saving = false;
        _error = err;
      });
      return;
    }
    widget.onBooked?.call(name);
    Navigator.of(context).pop(widget.start);
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 12),
        child: Text(text, style: AppTheme.mono(size: 9.5, color: AppTheme.ink900, weight: FontWeight.w700)),
      );

  Widget _field(TextEditingController ctrl, {String hint = '', TextInputType? keyboard, int maxLines = 1}) =>
      Container(
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.ink900, width: 1.5),
        ),
        child: TextField(
          controller: ctrl,
          keyboardType: keyboard,
          maxLines: maxLines,
          textCapitalization: keyboard == null ? TextCapitalization.words : TextCapitalization.none,
          style: AppTheme.body(size: 13, color: AppTheme.ink900),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTheme.body(size: 12, color: AppTheme.muted),
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final agent = widget.agentName.trim().isEmpty ? '—' : widget.agentName.trim();
    final when = '${DateFormat('EEEE, MMMM d, yyyy').format(widget.start)} · ${_slotLabel(widget.start)}';

    return Dialog(
      backgroundColor: AppTheme.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.ink900, width: 1.5),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titleRow('BOOK DEMO SLOT'),
            const SizedBox(height: 8),
            // "Arun · Thursday, September 24, 2026 · 12:00 PM - 1:00 PM": the team leader running the demo
            Text(
              '${widget.teamLeaderName.trim().isNotEmpty ? widget.teamLeaderName.trim() : agent} · $when',
              style: AppTheme.mono(size: 10.5, color: AppTheme.ink700),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppTheme.ink900),
            _label('CALLER'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.paper,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.ink900, width: 1.5),
              ),
              child: Text(agent, style: AppTheme.body(size: 13, color: AppTheme.ink900)),
            ),
            _label('CLIENT NAME'),
            _field(_nameCtrl, hint: 'Client name'),
            _label('CLIENT PHONE'),
            _field(_phoneCtrl, hint: 'Client phone', keyboard: TextInputType.phone),
            _label('CLASS / COURSE'),
            _field(_courseCtrl, hint: 'Class / course'),
            _label('NOTES (OPTIONAL)'),
            _field(_notesCtrl, hint: 'Notes', keyboard: TextInputType.multiline, maxLines: 3),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: AppTheme.bodyBold(size: 12, color: Colors.red.shade700)),
            ],
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: _saving ? null : () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppTheme.ink900, width: 1.5),
                    ),
                    child: Text('CLOSE', style: AppTheme.mono(size: 10.5, color: AppTheme.ink900, weight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _saving ? null : _submit,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.greenNeon,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppTheme.ink900, width: 1.5),
                      boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                    ),
                    child: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.ink900))
                        : Text('BOOK SLOT', style: AppTheme.mono(size: 10.5, color: AppTheme.ink900, weight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
