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
  int _selectedDateIndex = 0; // 0 = TODAY, 1 = TOMORROW, 2 = Day+2, 3 = Day+3, 4 = CALENDAR PICKED
  int _selectedTimeIndex = 3; // 0 = 10:00 AM, 1 = 12:00 PM, 2 = 3:00 PM, 3 = 5:30 PM, 4 = 7:00 PM
  String? _customDateFormatted;
  DateTime? _pickedRawDate;
  final TextEditingController _customTimeCtrl = TextEditingController();

  late List<String> _dateLabels;
  final List<String> _timeLabels = ['10:00 AM', '12:00 PM', '3:00 PM', '5:30 PM', '7:00 PM'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final day3 = DateFormat('d MMM').format(now.add(const Duration(days: 2))).toUpperCase();
    final day4 = DateFormat('d MMM').format(now.add(const Duration(days: 3))).toUpperCase();
    _dateLabels = ['TODAY', 'TOMORROW', day3, day4];
  }

  @override
  void dispose() {
    _customTimeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCalendarDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
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
      setState(() {
        _pickedRawDate = picked;
        _customDateFormatted = DateFormat('d MMM').format(picked).toUpperCase();
        _selectedDateIndex = 4;
      });
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 17, minute: 30),
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
      final now = DateTime.now();
      final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
      setState(() {
        _customTimeCtrl.text = DateFormat('h:mm a').format(dt);
      });
    }
  }

  DateTime _computeSelectedDateTime() {
    final now = DateTime.now();
    DateTime targetDate = now;

    if (_selectedDateIndex == 0) {
      targetDate = now;
    } else if (_selectedDateIndex == 1) {
      targetDate = now.add(const Duration(days: 1));
    } else if (_selectedDateIndex == 2) {
      targetDate = now.add(const Duration(days: 2));
    } else if (_selectedDateIndex == 3) {
      targetDate = now.add(const Duration(days: 3));
    } else if (_selectedDateIndex == 4 && _pickedRawDate != null) {
      targetDate = _pickedRawDate!;
    }

    String selectedTimeStr = _timeLabels[_selectedTimeIndex.clamp(0, _timeLabels.length - 1)];
    if (_customTimeCtrl.text.isNotEmpty) {
      selectedTimeStr = _customTimeCtrl.text;
    }

    int hour = 17;
    int minute = 30;

    try {
      final parsedTime = DateFormat('h:mm a').parse(selectedTimeStr);
      hour = parsedTime.hour;
      minute = parsedTime.minute;
    } catch (_) {
      try {
        final parsedTime2 = DateFormat('h:mm A').parse(selectedTimeStr);
        hour = parsedTime2.hour;
        minute = parsedTime2.minute;
      } catch (_) {}
    }

    return DateTime(targetDate.year, targetDate.month, targetDate.day, hour, minute);
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context, listen: false);

    final selectedDateStr = _selectedDateIndex == 4 && _customDateFormatted != null
        ? _customDateFormatted!
        : _dateLabels[_selectedDateIndex.clamp(0, _dateLabels.length - 1)];

    final selectedTimeStr = _customTimeCtrl.text.isNotEmpty
        ? _customTimeCtrl.text
        : _timeLabels[_selectedTimeIndex.clamp(0, _timeLabels.length - 1)];

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
            const SizedBox(height: 16),

            // Section Header: SELECT DATE
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(width: 8, height: 8, color: AppTheme.greenNeon),
                    const SizedBox(width: 8),
                    Text(
                      'SELECT DATE',
                      style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.18),
                    ),
                  ],
                ),

                // CALENDAR PICKER BUTTON
                GestureDetector(
                  onTap: _pickCalendarDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _selectedDateIndex == 4 ? AppTheme.ink900 : AppTheme.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppTheme.ink900, width: 1.2),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_month,
                          size: 13,
                          color: _selectedDateIndex == 4 ? AppTheme.limeYellow : AppTheme.ink900,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _selectedDateIndex == 4 && _customDateFormatted != null
                              ? _customDateFormatted!
                              : 'PICK FROM CALENDAR',
                          style: AppTheme.label(
                            size: 8.5,
                            color: _selectedDateIndex == 4 ? AppTheme.limeYellow : AppTheme.ink900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Date Quick Pills Row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int idx = 0; idx < _dateLabels.length; idx++) ...[
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedDateIndex = idx),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: _selectedDateIndex == idx ? AppTheme.ink900 : AppTheme.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppTheme.ink900, width: 1.2),
                          ),
                          child: Text(
                            _dateLabels[idx],
                            style: AppTheme.label(
                              size: 9,
                              color: _selectedDateIndex == idx ? AppTheme.limeYellow : AppTheme.ink900,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Section Header: SELECT TIME
            Row(
              children: [
                Container(width: 8, height: 8, color: AppTheme.greenNeon),
                const SizedBox(width: 8),
                Text(
                  'SELECT TIME',
                  style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.18),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Time Quick Pills Row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int idx = 0; idx < _timeLabels.length; idx++) ...[
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _selectedTimeIndex = idx;
                          _customTimeCtrl.clear();
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: (_selectedTimeIndex == idx && _customTimeCtrl.text.isEmpty)
                                ? AppTheme.ink900
                                : AppTheme.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppTheme.ink900, width: 1.2),
                          ),
                          child: Text(
                            _timeLabels[idx],
                            style: AppTheme.label(
                              size: 9,
                              color: (_selectedTimeIndex == idx && _customTimeCtrl.text.isEmpty)
                                  ? AppTheme.limeYellow
                                  : AppTheme.ink900,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // CUSTOM TIME / CLOCK PICKER FIELD
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.ink900, width: 1.5),
                boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
              ),
              child: TextField(
                controller: _customTimeCtrl,
                readOnly: true,
                onTap: _pickTime,
                style: AppTheme.mono(size: 13, color: AppTheme.ink900),
                decoration: const InputDecoration(
                  hintText: 'Or tap to pick custom time from clock...',
                  hintStyle: TextStyle(color: AppTheme.muted, fontSize: 12),
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.access_time_rounded, size: 18, color: AppTheme.ink900),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // SAVE RESCHEDULE BUTTON
            NeoButton(
              backgroundColor: AppTheme.ink900,
              shadowColor: AppTheme.greenNeon,
              onTap: () {
                final targetDateTime = _computeSelectedDateTime();

                tele.addScheduledCallback(
                  name: widget.contactName,
                  phone: widget.phone,
                  scheduledTime: targetDateTime,
                  note: 'Rescheduled follow-up call',
                );

                Navigator.of(context).pop();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppTheme.ink900,
                    content: Text(
                      'Follow-up scheduled for ${widget.contactName} ($selectedDateStr · $selectedTimeStr)',
                      style: AppTheme.bodyBold(size: 12, color: AppTheme.limeYellow),
                    ),
                  ),
                );
              },
              child: Center(
                child: Text(
                  'SAVE — $selectedDateStr · $selectedTimeStr →',
                  style: AppTheme.label(size: 11, color: AppTheme.limeYellow, letterSpacing: 0.14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
