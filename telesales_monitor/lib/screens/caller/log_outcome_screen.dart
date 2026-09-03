import 'dart:async';
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
  LeadStatus _selectedStatus = LeadStatus.interested;
  final TextEditingController _notesCtrl = TextEditingController(text: 'Wants pricing deck before demo...');
  bool _sendWhatsAppBrochure = true;
  String _selectedCallbackStr = 'TOMORROW · 10 AM';
  DateTime? _selectedCallbackTime;

  int _countdownSeconds = 15;
  Timer? _countdownTimer;
  bool _isCountdownPaused = false;

  @override
  void initState() {
    super.initState();
    _selectedCallbackTime = DateTime.now().add(const Duration(days: 1)).copyWith(hour: 10, minute: 0);
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (!_isCountdownPaused) {
        if (_countdownSeconds > 0) {
          setState(() => _countdownSeconds--);
        } else {
          timer.cancel();
          _triggerNextCallAutomatically();
        }
      }
    });
  }

  void _togglePauseCountdown() {
    setState(() => _isCountdownPaused = !_isCountdownPaused);
  }

  Future<void> _triggerNextCallAutomatically() async {
    final tele = Provider.of<TeleProvider>(context, listen: false);
    final navigator = Navigator.of(context);
    await tele.saveCallOutcomeAndNext(
      status: _selectedStatus,
      note: _notesCtrl.text,
      sendBrochure: _sendWhatsAppBrochure,
      callbackTime: _selectedCallbackTime,
    );

    if (mounted) {
      if (tele.activeCallLead != null) {
        navigator.pushReplacement(
          MaterialPageRoute(
            builder: (_) => CallSessionScreen(lead: tele.activeCallLead),
          ),
        );
      } else {
        navigator.pop();
      }
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _pickCallbackDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
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

    if (pickedDate != null && mounted) {
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

      if (pickedTime != null) {
        final fullDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        setState(() {
          _selectedCallbackTime = fullDateTime;
          _selectedCallbackStr = DateFormat('d MMM · h:mm a').format(fullDateTime).toUpperCase();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);
    final lead = widget.lead ?? tele.activeCallLead ?? (tele.sessionQueue.isNotEmpty ? tele.sessionQueue[tele.sessionIndex.clamp(0, tele.sessionQueue.length - 1)] : LeadModel(
      id: 'demo',
      name: 'Ganesh Enterprises',
      phone: '+91 98400 11223',
      status: LeadStatus.interested,
      attempts: 1,
      dateAdded: DateTime.now(),
      lastCallDate: DateTime.now(),
      note: '',
    ));

    final nextLead = tele.nextSessionLead;
    final remainingCount = tele.remainingSessionCount;

    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Subtitle
              Text(
                'CALL ENDED · 3M 12S TALK',
                style: AppTheme.mono(size: 11, color: AppTheme.greenDark, weight: FontWeight.w700),
              ),
              const SizedBox(height: 4),

              // Main Title
              Text(
                'LOG THE OUTCOME.',
                style: AppTheme.headline(size: 32, color: AppTheme.ink900),
              ),
              const SizedBox(height: 4),

              // Contact Details
              Text(
                '${lead.name} · ${lead.phone}',
                style: AppTheme.mono(size: 12, color: AppTheme.ink700),
              ),
              const SizedBox(height: 14),

              // Time Badges Strip
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _TimeBadge(label: 'START 11:42', isDark: true),
                  _TimeBadge(label: 'END 11:45', isDark: true),
                  _TimeBadge(label: 'TALK 3M 12S', isDark: true),
                  _TimeBadge(label: 'WRAP-UP 00:18', isLime: true),
                ],
              ),
              const SizedBox(height: 16),

              // 2x2 Outcome Grid
              Row(
                children: [
                  Expanded(
                    child: _OutcomeButton(
                      label: 'FOLLOW UP',
                      isSelected: _selectedStatus == LeadStatus.followUp,
                      activeBg: AppTheme.limeYellow,
                      activeFg: AppTheme.ink900,
                      onTap: () => setState(() => _selectedStatus = LeadStatus.followUp),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _OutcomeButton(
                      label: 'BOOK DEMO',
                      isSelected: _selectedStatus == LeadStatus.bookDemo,
                      activeBg: AppTheme.greenNeon,
                      activeFg: AppTheme.ink900,
                      onTap: () => setState(() => _selectedStatus = LeadStatus.bookDemo),
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
                      onTap: () => setState(() => _selectedStatus = LeadStatus.demoReschedule),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _OutcomeButton(
                      label: 'DEMO DONE',
                      isSelected: _selectedStatus == LeadStatus.demoDone,
                      activeBg: AppTheme.ink900,
                      activeFg: AppTheme.limeYellow,
                      onTap: () => setState(() => _selectedStatus = LeadStatus.demoDone),
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
                      onTap: () => setState(() => _selectedStatus = LeadStatus.interested),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _OutcomeButton(
                      label: 'NOT INTERESTED',
                      isSelected: _selectedStatus == LeadStatus.notInterested,
                      activeBg: AppTheme.white,
                      activeFg: AppTheme.ink900,
                      onTap: () => setState(() => _selectedStatus = LeadStatus.notInterested),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Notes Input Field
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
                    hintText: 'Add call notes, client response...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // WhatsApp Brochure Toggle Row
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
                    Text(
                      'WHATSAPP BROCHURE',
                      style: AppTheme.label(size: 10.5, color: AppTheme.ink900, letterSpacing: 0.12),
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

              // Callback Schedule Row
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
                    Text(
                      'CALLBACK',
                      style: AppTheme.label(size: 10.5, color: AppTheme.ink900, letterSpacing: 0.12),
                    ),
                    GestureDetector(
                      onTap: _pickCallbackDateTime,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.limeYellow,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppTheme.ink900, width: 1.2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _selectedCallbackStr,
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

              // Next Up Strip with Countdown Ticker & Controls
              if (nextLead != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.ink900,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.ink900, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _isCountdownPaused ? AppTheme.orangePill : AppTheme.greenNeon,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _isCountdownPaused ? 'PAUSED' : 'AUTO-DIAL IN ${_countdownSeconds}S',
                                  style: AppTheme.label(size: 8, color: AppTheme.ink900),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'NEXT IN QUEUE',
                                style: AppTheme.mono(size: 8.5, color: AppTheme.lightMuted),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              GestureDetector(
                                onTap: _togglePauseCountdown,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.ink800,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: AppTheme.lightMuted, width: 0.8),
                                  ),
                                  child: Text(
                                    _isCountdownPaused ? '▶ RESUME' : '⏸ STOP',
                                    style: AppTheme.mono(size: 8.5, color: AppTheme.limeYellow, weight: FontWeight.w700),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () {
                                  _countdownTimer?.cancel();
                                  tele.saveCallOutcomeAndNext(
                                    status: _selectedStatus,
                                    note: _notesCtrl.text,
                                    sendBrochure: _sendWhatsAppBrochure,
                                    callbackTime: _selectedCallbackTime,
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.ink800,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: AppTheme.greenGrass, width: 0.8),
                                  ),
                                  child: Text(
                                    'SKIP →',
                                    style: AppTheme.mono(size: 8.5, color: AppTheme.greenGrass, weight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${nextLead.name} · ${nextLead.phone}',
                        style: AppTheme.bodyBold(size: 12.5, color: AppTheme.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),

              // Main Save & Dial Next Button
              GestureDetector(
                onTap: () async {
                  final navigator = Navigator.of(context);
                  await tele.saveCallOutcomeAndNext(
                    status: _selectedStatus,
                    note: _notesCtrl.text,
                    sendBrochure: _sendWhatsAppBrochure,
                    callbackTime: _selectedCallbackTime,
                  );

                  if (tele.activeCallLead != null) {
                    navigator.pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => CallSessionScreen(lead: tele.activeCallLead),
                      ),
                    );
                  } else {
                    navigator.pop();
                  }
                },
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
              const SizedBox(height: 10),

              // Secondary: Save & Take a Break Button
              GestureDetector(
                onTap: () async {
                  final navigator = Navigator.of(context);
                  await tele.saveCallOutcomeAndNext(
                    status: _selectedStatus,
                    note: _notesCtrl.text,
                    sendBrochure: _sendWhatsAppBrochure,
                    callbackTime: _selectedCallbackTime,
                    takeBreak: true,
                  );
                  navigator.pop();
                },
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
