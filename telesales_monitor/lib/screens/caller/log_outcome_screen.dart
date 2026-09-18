import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../providers/tele_provider.dart';
import '../../models/lead_model.dart';
import 'call_session_screen.dart';

class LogOutcomeScreen extends StatefulWidget {
  final LeadModel? lead;

  const LogOutcomeScreen({super.key, this.lead});

  @override
  State<LogOutcomeScreen> createState() => _LogOutcomeScreenState();
}

class _LogOutcomeScreenState extends State<LogOutcomeScreen> {
  LeadStatus? _selectedStatus; // nothing is pre-selected: the caller must choose
  final TextEditingController _notesCtrl = TextEditingController();
  bool _sendWhatsAppBrochure = false; // opt-in
  DateTime? _selectedCallbackTime; // optional
  bool _saving = false;

  static const Set<LeadStatus> _closedStatuses = {LeadStatus.notInterested, LeadStatus.lost, LeadStatus.won};

  bool get _callbackAllowed => _selectedStatus == null || !_closedStatuses.contains(_selectedStatus);

  void _selectStatus(LeadStatus s) {
    setState(() {
      _selectedStatus = s;
      if (_closedStatuses.contains(s)) _selectedCallbackTime = null;
    });
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCallbackDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
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

    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
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
    if (pickedTime == null || !mounted) return;
    final full = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute);
    if (!full.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.ink900,
          content: Text('Pick a callback time in the future.', style: AppTheme.bodyBold(size: 12, color: AppTheme.limeYellow)),
        ),
      );
      return;
    }
    setState(() => _selectedCallbackTime = full);
  }

  /// Saves the outcome. [dialNext] dials the next lead (explicit user action only).
  Future<void> _save(TeleProvider tele, {bool dialNext = false, bool takeBreak = false}) async {
    final status = _selectedStatus;
    if (status == null || _saving) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    await tele.saveCallOutcomeAndNext(
      status: status,
      note: _notesCtrl.text.trim(),
      sendBrochure: _sendWhatsAppBrochure,
      callbackTime: _callbackAllowed ? _selectedCallbackTime : null,
      takeBreak: takeBreak,
      dialNext: dialNext,
    );
    if (!mounted) return;
    if (dialNext && tele.activeCallLead != null) {
      navigator.pushReplacement(MaterialPageRoute(builder: (_) => CallSessionScreen(lead: tele.activeCallLead)));
    } else {
      navigator.pop();
    }
  }

  void _skip(TeleProvider tele) {
    // Moves on without saving anything and without dialing.
    tele.skipSessionLead();
    final next = tele.activeCallLead;
    if (next != null) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => CallSessionScreen(lead: next)));
    } else {
      Navigator.of(context).pop();
    }
  }

  String _hm(DateTime? t) => t == null ? '—' : DateFormat('h:mm a').format(t).toUpperCase();

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);
    final lead = widget.lead ?? tele.activeCallLead;

    if (lead == null) {
      return Scaffold(
        backgroundColor: AppTheme.paper,
        appBar: AppBar(backgroundColor: AppTheme.paper, elevation: 0),
        body: Center(
          child: Text('No call to log.', style: AppTheme.body(size: 14, color: AppTheme.muted)),
        ),
      );
    }

    final nextLead = tele.nextSessionLead;
    final remainingCount = tele.remainingSessionCount;
    final startedAt = tele.sessionCallStartedAt;
    final endedAt = tele.sessionCallEndedAt;
    final deviceCall = tele.latestDeviceCallFor(lead.phone, since: startedAt);
    final talk = deviceCall != null && deviceCall.duration.inSeconds > 0 ? deviceCall.durationFormatted.toUpperCase() : '—';
    final canSave = _selectedStatus != null && !_saving;

    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CALL ENDED · TALK $talk',
                style: AppTheme.mono(size: 11, color: AppTheme.greenDark, weight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'LOG THE OUTCOME.',
                style: AppTheme.headline(size: 32, color: AppTheme.ink900),
              ),
              const SizedBox(height: 4),
              Text(
                '${lead.name} · ${lead.phone}',
                style: AppTheme.mono(size: 12, color: AppTheme.ink700),
              ),
              const SizedBox(height: 14),

              // Real times: dialed / closed from the session, talk time from the device call log
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _TimeBadge(label: 'DIALED ${_hm(startedAt)}', isDark: true),
                  _TimeBadge(label: 'CLOSED ${_hm(endedAt)}', isDark: true),
                  _TimeBadge(label: 'TALK $talk', isLime: true),
                ],
              ),
              const SizedBox(height: 16),

              Text('OUTCOME', style: AppTheme.label(size: 9.5, color: AppTheme.muted, letterSpacing: 0.14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _OutcomeButton(
                      label: 'FOLLOW UP',
                      isSelected: _selectedStatus == LeadStatus.followUp,
                      activeBg: AppTheme.limeYellow,
                      activeFg: AppTheme.ink900,
                      onTap: () => _selectStatus(LeadStatus.followUp),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _OutcomeButton(
                      label: 'BOOK DEMO',
                      isSelected: _selectedStatus == LeadStatus.bookDemo,
                      activeBg: AppTheme.greenNeon,
                      activeFg: AppTheme.ink900,
                      onTap: () => _selectStatus(LeadStatus.bookDemo),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _OutcomeButton(
                      label: 'DEMO RESCHEDULE',
                      isSelected: _selectedStatus == LeadStatus.demoReschedule,
                      activeBg: AppTheme.paper,
                      activeFg: AppTheme.ink900,
                      onTap: () => _selectStatus(LeadStatus.demoReschedule),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _OutcomeButton(
                      label: 'DEMO DONE',
                      isSelected: _selectedStatus == LeadStatus.demoDone,
                      activeBg: AppTheme.ink900,
                      activeFg: AppTheme.limeYellow,
                      onTap: () => _selectStatus(LeadStatus.demoDone),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _OutcomeButton(
                      label: 'NOT PICKED UP',
                      isSelected: _selectedStatus == LeadStatus.notPickup,
                      activeBg: AppTheme.orangePill,
                      activeFg: AppTheme.ink900,
                      onTap: () => _selectStatus(LeadStatus.notPickup),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _OutcomeButton(
                      label: 'BUSY',
                      isSelected: _selectedStatus == LeadStatus.busyOnCall,
                      activeBg: AppTheme.orangePill,
                      activeFg: AppTheme.ink900,
                      onTap: () => _selectStatus(LeadStatus.busyOnCall),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _OutcomeButton(
                      label: 'INTERESTED',
                      isSelected: _selectedStatus == LeadStatus.interested,
                      activeBg: AppTheme.greenNeon,
                      activeFg: AppTheme.ink900,
                      onTap: () => _selectStatus(LeadStatus.interested),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _OutcomeButton(
                      label: 'NOT INTERESTED',
                      isSelected: _selectedStatus == LeadStatus.notInterested,
                      activeBg: AppTheme.white,
                      activeFg: AppTheme.ink900,
                      onTap: () => _selectStatus(LeadStatus.notInterested),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Notes (empty by default)
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.ink900, width: 1.5),
                  boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                ),
                child: TextField(
                  controller: _notesCtrl,
                  maxLines: 2,
                  style: AppTheme.body(size: 13, color: AppTheme.ink900),
                  decoration: const InputDecoration(
                    hintText: 'Add call notes, client response... (optional)',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // WhatsApp brochure: opt-in
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.ink900, width: 1.5),
                  boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'SEND WHATSAPP BROCHURE',
                        style: AppTheme.label(size: 10.5, color: AppTheme.ink900, letterSpacing: 0.12),
                      ),
                    ),
                    Switch(
                      value: _sendWhatsAppBrochure,
                      activeTrackColor: AppTheme.greenNeon,
                      activeThumbColor: AppTheme.white,
                      inactiveTrackColor: AppTheme.paper,
                      onChanged: (val) => setState(() => _sendWhatsAppBrochure = val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Optional callback
              if (_callbackAllowed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.ink900, width: 1.5),
                    boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'CALLBACK',
                          style: AppTheme.label(size: 10.5, color: AppTheme.ink900, letterSpacing: 0.12),
                        ),
                      ),
                      if (_selectedCallbackTime != null)
                        IconButton(
                          tooltip: 'Remove callback',
                          icon: const Icon(Icons.close, size: 18, color: AppTheme.ink900),
                          onPressed: () => setState(() => _selectedCallbackTime = null),
                        ),
                      GestureDetector(
                        onTap: _pickCallbackDateTime,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _selectedCallbackTime != null ? AppTheme.limeYellow : AppTheme.paper,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppTheme.ink900, width: 1.2),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _selectedCallbackTime != null
                                    ? DateFormat('d MMM · h:mm a').format(_selectedCallbackTime!).toUpperCase()
                                    : 'NONE · SET',
                                style: AppTheme.mono(size: 10.5, color: AppTheme.ink900, weight: FontWeight.w700),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_drop_down, size: 16, color: AppTheme.ink900),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 18),

              // Next in queue (no auto-dial: the caller decides)
              if (nextLead != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.ink900,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.ink900, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('NEXT IN QUEUE', style: AppTheme.mono(size: 8.5, color: AppTheme.lightMuted)),
                            const SizedBox(height: 4),
                            Text(
                              '${nextLead.name} · ${nextLead.phone}',
                              style: AppTheme.bodyBold(size: 12.5, color: AppTheme.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _skip(tele),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.ink800,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppTheme.greenGrass, width: 0.8),
                          ),
                          child: Text(
                            'SKIP (DON\'T SAVE) →',
                            style: AppTheme.mono(size: 8.5, color: AppTheme.greenGrass, weight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),

              if (_selectedStatus == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Choose an outcome to save.', style: AppTheme.body(size: 11, color: AppTheme.muted)),
                ),

              // Save & dial next (explicit action)
              Opacity(
                opacity: canSave ? 1 : 0.4,
                child: GestureDetector(
                  onTap: canSave ? () => _save(tele, dialNext: remainingCount > 0) : null,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.ink900,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppTheme.ink900, width: 1.5),
                      boxShadow: AppTheme.neoShadow(color: AppTheme.ink900, offset: 4),
                    ),
                    child: Center(
                      child: Text(
                        remainingCount > 0 ? 'SAVE & DIAL NEXT · $remainingCount LEFT →' : 'SAVE & FINISH SESSION →',
                        style: AppTheme.label(size: 11.5, color: AppTheme.limeYellow, letterSpacing: 0.15),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              if (remainingCount > 0) ...[
                Opacity(
                  opacity: canSave ? 1 : 0.4,
                  child: GestureDetector(
                    onTap: canSave ? () => _save(tele, dialNext: false) : null,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppTheme.ink900, width: 1.5),
                        boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                      ),
                      child: Center(
                        child: Text(
                          'SAVE & STOP SESSION',
                          style: AppTheme.label(size: 10.5, color: AppTheme.ink900, letterSpacing: 0.12),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              Opacity(
                opacity: canSave ? 1 : 0.4,
                child: GestureDetector(
                  onTap: canSave ? () => _save(tele, takeBreak: true) : null,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppTheme.ink900, width: 1.5),
                      boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                    ),
                    child: Center(
                      child: Text(
                        'SAVE & TAKE A BREAK',
                        style: AppTheme.label(size: 10.5, color: AppTheme.ink900, letterSpacing: 0.12),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeBadge extends StatelessWidget {
  final String label;
  final bool isDark;
  final bool isLime;

  const _TimeBadge({
    required this.label,
    this.isDark = false,
    this.isLime = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isLime ? AppTheme.limeYellow : (isDark ? AppTheme.ink900 : AppTheme.white);
    final fg = isLime ? AppTheme.ink900 : (isDark ? AppTheme.limeYellow : AppTheme.ink900);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.ink900, width: 1.2),
      ),
      child: Text(
        label,
        style: AppTheme.mono(size: 9.5, color: fg, weight: FontWeight.w700),
      ),
    );
  }
}

class _OutcomeButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color activeBg;
  final Color activeFg;
  final VoidCallback onTap;

  const _OutcomeButton({
    required this.label,
    required this.isSelected,
    required this.activeBg,
    required this.activeFg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isSelected ? activeBg : AppTheme.white;
    final fg = isSelected ? activeFg : AppTheme.ink900;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppTheme.ink900, width: 1.5),
          boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTheme.label(size: 10.5, color: fg, letterSpacing: 0.1),
          ),
        ),
      ),
    );
  }
}
