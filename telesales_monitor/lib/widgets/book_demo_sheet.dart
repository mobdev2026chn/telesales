import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/lead_model.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Demo booking form shown after a call. Returns the booked slot start when the
/// demo was saved on the server, null when the caller closed it.
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

class BookDemoSheet extends StatefulWidget {
  final LeadModel lead;
  final String agentName;
  final ValueChanged<String>? onBooked;

  const BookDemoSheet({super.key, required this.lead, required this.agentName, this.onBooked});

  @override
  State<BookDemoSheet> createState() => _BookDemoSheetState();
}

class _BookDemoSheetState extends State<BookDemoSheet> {
  // Working hours 10 AM - 7 PM, 30 minute slots
  static const int _firstHour = 10;
  static const int _lastHour = 19;
  static const int _slotMinutes = 30;

  late final TextEditingController _nameCtrl;
  final TextEditingController _reasonCtrl = TextEditingController();
  late DateTime _date;
  TimeOfDay? _slot;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final name = widget.lead.name.trim();
    _nameCtrl = TextEditingController(text: name.toLowerCase() == 'unknown' ? '' : name);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Today while slots are still open, otherwise tomorrow
    _date = _slotsFor(today).isNotEmpty ? today : today.add(const Duration(days: 1));
    _nameCtrl.addListener(() => setState(() {}));
    _reasonCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  /// Slots of [day] that are still in the future.
  List<TimeOfDay> _slotsFor(DateTime day) {
    final now = DateTime.now();
    final out = <TimeOfDay>[];
    for (int m = _firstHour * 60; m < _lastHour * 60; m += _slotMinutes) {
      final t = TimeOfDay(hour: m ~/ 60, minute: m % 60);
      if (_at(day, t).isAfter(now)) out.add(t);
    }
    return out;
  }

  DateTime _at(DateTime day, TimeOfDay t) => DateTime(day.year, day.month, day.day, t.hour, t.minute);

  String _fmtTime(DateTime d) => DateFormat('h:mm a').format(d).toUpperCase();

  String _slotLabel(TimeOfDay t) {
    final start = _at(_date, t);
    return '${_fmtTime(start)} - ${_fmtTime(start.add(const Duration(minutes: _slotMinutes)))}';
  }

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
    if (picked == null || !mounted) return;
    setState(() {
      _date = picked;
      // Keep the chosen slot only if it is still open on the new date
      if (_slot != null && !_slotsFor(_date).contains(_slot)) _slot = null;
    });
  }

  Future<void> _book() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Enter the client name.');
    if (_slot == null) return setState(() => _error = 'Pick a time slot.');
    final scheduledAt = _at(_date, _slot!);
    if (!scheduledAt.isAfter(DateTime.now())) return setState(() => _error = 'That slot has passed. Pick another one.');
    setState(() {
      _saving = true;
      _error = null;
    });
    final err = await ApiService.bookDemo(
      leadId: widget.lead.id.startsWith('local_') || widget.lead.id == 'demo' ? '' : widget.lead.id,
      clientName: name,
      clientPhone: widget.lead.phone,
      scheduledAt: scheduledAt,
      slot: _slotLabel(_slot!),
      reason: _reasonCtrl.text.trim(),
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
    Navigator.of(context).pop(scheduledAt);
  }

  @override
  Widget build(BuildContext context) {
    final slots = _slotsFor(_date);
    final summaryRows = <List<String>>[
      ['CLIENT', _nameCtrl.text.trim().isEmpty ? '—' : _nameCtrl.text.trim()],
      ['PHONE', widget.lead.phone.isEmpty ? '—' : widget.lead.phone],
      ['AGENT', widget.agentName.isEmpty ? '—' : widget.agentName],
      ['DATE', DateFormat('EEE, d MMM yyyy').format(_date).toUpperCase()],
      ['TIME SLOT', _slot == null ? '—' : _slotLabel(_slot!)],
      ['REASON', _reasonCtrl.text.trim().isEmpty ? '—' : _reasonCtrl.text.trim()],
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
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
              Text('BOOK A DEMO', style: AppTheme.headline(size: 28, color: AppTheme.ink900)),
              const SizedBox(height: 16),

              _label('CLIENT NAME'),
              _box(
                TextField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  style: AppTheme.bodyBold(size: 14, color: AppTheme.ink900),
                  decoration: const InputDecoration(
                    hintText: 'Client name',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              _label('AGENT (CALLER)'),
              _box(
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Text(
                    widget.agentName.isEmpty ? '—' : widget.agentName,
                    style: AppTheme.bodyBold(size: 14, color: AppTheme.ink900),
                  ),
                ),
                color: AppTheme.paper,
              ),
              const SizedBox(height: 12),

              _label('DATE'),
              GestureDetector(
                onTap: _pickDate,
                child: _box(
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 16, color: AppTheme.ink900),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            DateFormat('EEE, d MMM yyyy').format(_date).toUpperCase(),
                            style: AppTheme.mono(size: 12, color: AppTheme.ink900, weight: FontWeight.w700),
                          ),
                        ),
                        Text('CHANGE', style: AppTheme.mono(size: 10, color: AppTheme.greenDark, weight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              _label('TIME SLOT'),
              if (slots.isEmpty)
                Text('No slots left on this day. Pick another date.', style: AppTheme.body(size: 12, color: AppTheme.muted))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: slots.map((t) {
                    final selected = _slot == t;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _slot = t;
                        _error = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected ? AppTheme.ink900 : AppTheme.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppTheme.ink900, width: 1.2),
                        ),
                        child: Text(
                          _fmtTime(_at(_date, t)),
                          style: AppTheme.mono(size: 11, color: selected ? AppTheme.limeYellow : AppTheme.ink900, weight: FontWeight.w700),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 12),

              _label('REASON / NOTES'),
              _box(
                TextField(
                  controller: _reasonCtrl,
                  maxLines: 3,
                  maxLength: 2000,
                  style: AppTheme.body(size: 13, color: AppTheme.ink900),
                  decoration: const InputDecoration(
                    hintText: 'Why the client wants a demo, what to show...',
                    border: InputBorder.none,
                    counterText: '',
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Summary of everything that will be saved
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.ink900,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.ink900, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SUMMARY', style: AppTheme.mono(size: 10, color: AppTheme.limeYellow, weight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    ...summaryRows.map((r) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 84,
                                child: Text(r[0], style: AppTheme.mono(size: 9.5, color: AppTheme.lightMuted)),
                              ),
                              Expanded(
                                child: Text(r[1], style: AppTheme.bodyBold(size: 12.5, color: AppTheme.white)),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_error!, style: AppTheme.bodyBold(size: 12, color: Colors.red.shade700)),
                ),

              Opacity(
                opacity: _saving ? 0.6 : 1,
                child: GestureDetector(
                  onTap: _saving ? null : _book,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.greenNeon,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppTheme.ink900, width: 1.5),
                      boxShadow: AppTheme.neoShadow(color: AppTheme.ink900, offset: 4),
                    ),
                    child: Center(
                      child: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.ink900))
                          : Text('BOOK APPOINTMENT →', style: AppTheme.label(size: 11.5, color: AppTheme.ink900, letterSpacing: 0.15)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: AppTheme.label(size: 9.5, color: AppTheme.muted, letterSpacing: 0.14)),
      );

  Widget _box(Widget child, {Color color = AppTheme.white}) => Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.ink900, width: 1.5),
          boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
        ),
        child: child,
      );
}
