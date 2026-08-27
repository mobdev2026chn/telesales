import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import 'neo_button.dart';
import '../providers/tele_provider.dart';

class RescheduleSheet extends StatefulWidget {
  final String contactName;
  final String phone;

  const RescheduleSheet({
    super.key,
    required this.contactName,
    required this.phone,
  });

  static void show(BuildContext context, {required String contactName, required String phone}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RescheduleSheet(contactName: contactName, phone: phone),
    );
  }

  @override
  State<RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends State<RescheduleSheet> {
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  final TextEditingController _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = now;
    final nextHour = now.hour + 1 > 23 ? 23 : now.hour + 1;
    _selectedTime = TimeOfDay(hour: nextHour, minute: 0);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.ink900,
              onPrimary: AppTheme.limeYellow,
              onSurface: AppTheme.ink900,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.ink900,
              onPrimary: AppTheme.limeYellow,
              onSurface: AppTheme.ink900,
            ),
          ),
          child: child!,
        );
      },
    );

    if (time != null && mounted) {
      setState(() => _selectedTime = time);
    }
  }

  DateTime _getCombinedDateTime() {
    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
  }

  String _formatDateDisplay() {
    final now = DateTime.now();
    if (_selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day) {
      return 'TODAY (${DateFormat('d MMM').format(_selectedDate).toUpperCase()})';
    }
    final tom = now.add(const Duration(days: 1));
    if (_selectedDate.year == tom.year &&
        _selectedDate.month == tom.month &&
        _selectedDate.day == tom.day) {
      return 'TOMORROW (${DateFormat('d MMM').format(_selectedDate).toUpperCase()})';
    }
    return DateFormat('EEE, d MMM yyyy').format(_selectedDate).toUpperCase();
  }

  String _formatTimeDisplay() {
    final dt = DateTime(2026, 1, 1, _selectedTime.hour, _selectedTime.minute);
    return DateFormat('h:mm a').format(dt).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context, listen: false);
    final dateStr = _formatDateDisplay();
    final timeStr = _formatTimeDisplay();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.muted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Top Header & Close Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text('RESCHEDULE', style: AppTheme.headline(size: 22, color: AppTheme.ink900)),
                    Text('.', style: AppTheme.headline(size: 22, color: AppTheme.greenNeon)),
                  ],
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.ink900, width: 1.2),
                    ),
                    child: const Icon(Icons.close, size: 16, color: AppTheme.ink900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Target Contact Name & Phone
            Text(
              'Follow-up call with ${widget.contactName.toUpperCase()}',
              style: AppTheme.bodyBold(size: 13, color: AppTheme.ink900),
            ),
            Text(
              widget.phone,
              style: AppTheme.mono(size: 11, color: AppTheme.muted),
            ),
            const SizedBox(height: 18),

            // SECTION 1: CALENDAR DATE PICKER SELECTION FIELD
            Row(
              children: [
                Container(width: 8, height: 8, color: AppTheme.greenNeon),
                const SizedBox(width: 8),
                Text(
                  'DATE',
                  style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.18),
                ),
              ],
            ),
            const SizedBox(height: 8),

            GestureDetector(
              onTap: _pickDate,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.ink900, width: 1.5),
                  boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_month_rounded, size: 20, color: AppTheme.ink900),
                        const SizedBox(width: 12),
                        Text(
                          dateStr,
                          style: AppTheme.label(size: 11, color: AppTheme.ink900, letterSpacing: 0.12),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.paper,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppTheme.ink900, width: 1),
                      ),
                      child: Text(
                        'CHANGE DATE',
                        style: AppTheme.label(size: 8, color: AppTheme.ink900),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // SECTION 2: CLOCK TIME PICKER SELECTION FIELD
            Row(
              children: [
                Container(width: 8, height: 8, color: AppTheme.greenNeon),
                const SizedBox(width: 8),
                Text(
                  'TIME',
                  style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.18),
                ),
              ],
            ),
            const SizedBox(height: 8),

            GestureDetector(
              onTap: _pickTime,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.ink900, width: 1.5),
                  boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded, size: 20, color: AppTheme.ink900),
                        const SizedBox(width: 12),
                        Text(
                          timeStr,
                          style: AppTheme.mono(size: 14, color: AppTheme.ink900),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.paper,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppTheme.ink900, width: 1),
                      ),
                      child: Text(
                        'CHANGE TIME',
                        style: AppTheme.label(size: 8, color: AppTheme.ink900),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // SECTION 3: REMARKS & REASON NOTE
            Row(
              children: [
                Container(width: 8, height: 8, color: AppTheme.greenNeon),
                const SizedBox(width: 8),
                Text(
                  'REASON / NOTE',
                  style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.18),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.ink900, width: 1.5),
                boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
              ),
              child: TextField(
                controller: _noteCtrl,
                style: AppTheme.body(size: 12, color: AppTheme.ink900),
                decoration: const InputDecoration(
                  hintText: 'Enter reason or remark...',
                  hintStyle: TextStyle(color: AppTheme.muted, fontSize: 12),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 22),

            // SAVE RESCHEDULE ACTION BUTTON
            NeoButton(
              backgroundColor: AppTheme.ink900,
              shadowColor: AppTheme.greenNeon,
              onTap: () {
                final targetDateTime = _getCombinedDateTime();

                tele.addScheduledCallback(
                  name: widget.contactName,
                  phone: widget.phone,
                  scheduledTime: targetDateTime,
                  note: _noteCtrl.text.isNotEmpty ? _noteCtrl.text : 'Rescheduled follow-up call',
                );

                Navigator.of(context).pop();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppTheme.ink900,
                    content: Text(
                      'Follow-up scheduled for ${widget.contactName} ($dateStr · $timeStr)',
                      style: AppTheme.bodyBold(size: 12, color: AppTheme.limeYellow),
                    ),
                  ),
                );
              },
              child: Center(
                child: Text(
                  'CONFIRM RESCHEDULE →',
                  style: AppTheme.label(size: 11.5, color: AppTheme.limeYellow, letterSpacing: 0.14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
