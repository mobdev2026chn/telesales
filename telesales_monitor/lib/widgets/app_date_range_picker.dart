import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

Future<DateTimeRange?> showAppDateRangePicker({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialDateRange,
}) {
  return showDialog<DateTimeRange>(
    context: context,
    builder: (_) => _AppDateRangeDialog(
      firstDate: DateUtils.dateOnly(firstDate),
      lastDate: DateUtils.dateOnly(lastDate),
      initialDateRange: initialDateRange,
    ),
  );
}

class _AppDateRangeDialog extends StatefulWidget {
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTimeRange? initialDateRange;

  const _AppDateRangeDialog({
    required this.firstDate,
    required this.lastDate,
    required this.initialDateRange,
  });

  @override
  State<_AppDateRangeDialog> createState() => _AppDateRangeDialogState();
}

class _AppDateRangeDialogState extends State<_AppDateRangeDialog> {
  DateTime? _start;
  DateTime? _end;
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDateRange;
    if (initial != null &&
        !initial.start.isBefore(widget.firstDate) &&
        !initial.end.isAfter(widget.lastDate)) {
      _start = DateUtils.dateOnly(initial.start);
      _end = DateUtils.dateOnly(initial.end);
    }
    _visibleMonth = DateTime(
      (_start ?? widget.lastDate).year,
      (_start ?? widget.lastDate).month,
    );
  }

  bool _isSelectable(DateTime date) =>
      !date.isBefore(widget.firstDate) && !date.isAfter(widget.lastDate);

  bool _sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  void _changeMonth(int amount) {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + amount);
    if (next.isBefore(
          DateTime(widget.firstDate.year, widget.firstDate.month),
        ) ||
        next.isAfter(DateTime(widget.lastDate.year, widget.lastDate.month))) {
      return;
    }
    setState(() => _visibleMonth = next);
  }

  void _selectDate(DateTime date) {
    if (!_isSelectable(date)) return;
    setState(() {
      if (_start == null || _end != null || date.isBefore(_start!)) {
        _start = date;
        _end = null;
      } else {
        _end = date;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final monthStart = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final leadingDays = monthStart.weekday % 7;
    final daysInMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    ).day;
    final firstMonth = DateTime(widget.firstDate.year, widget.firstDate.month);
    final lastMonth = DateTime(widget.lastDate.year, widget.lastDate.month);

    return Dialog(
      backgroundColor: AppTheme.paper,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.ink900, width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppTheme.limeYellow,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.ink900, width: 1.2),
                    ),
                    child: const Icon(
                      Icons.date_range_rounded,
                      color: AppTheme.ink900,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SELECT DATE RANGE',
                          style: AppTheme.label(
                            size: 11,
                            color: AppTheme.ink900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _end == null
                              ? 'Choose a start and end date'
                              : 'Range ready to apply',
                          style: AppTheme.body(
                            size: 11,
                            color: AppTheme.ink700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    color: AppTheme.ink700,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.ink900, width: 1),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _RangeDateLabel(label: 'START', date: _start),
                    ),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 17,
                      color: AppTheme.greenDark,
                    ),
                    Expanded(
                      child: _RangeDateLabel(
                        label: 'END',
                        date: _end,
                        alignEnd: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous month',
                    onPressed: _sameMonth(_visibleMonth, firstMonth)
                        ? null
                        : () => _changeMonth(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                    color: AppTheme.ink900,
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        DateFormat('MMMM yyyy').format(_visibleMonth),
                        style: AppTheme.bodyBold(
                          size: 15,
                          color: AppTheme.ink900,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    onPressed: _sameMonth(_visibleMonth, lastMonth)
                        ? null
                        : () => _changeMonth(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                    color: AppTheme.ink900,
                  ),
                ],
              ),
              Row(
                children: const ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                    .map(
                      (day) => Expanded(
                        child: Center(
                          child: Text(
                            day,
                            style: AppTheme.label(
                              size: 10,
                              color: AppTheme.ink700,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 6),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 42,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 1.18,
                ),
                itemBuilder: (context, index) {
                  final dayNumber = index - leadingDays + 1;
                  if (dayNumber < 1 || dayNumber > daysInMonth) {
                    return const SizedBox.shrink();
                  }
                  final date = DateTime(
                    _visibleMonth.year,
                    _visibleMonth.month,
                    dayNumber,
                  );
                  return _buildDay(date);
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.ink900,
                        side: const BorderSide(color: AppTheme.ink900),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('CANCEL'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _start != null && _end != null
                          ? () => Navigator.pop(
                              context,
                              DateTimeRange(start: _start!, end: _end!),
                            )
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.ink900,
                        foregroundColor: AppTheme.limeYellow,
                        disabledBackgroundColor: AppTheme.ink900.withValues(
                          alpha: 0.16,
                        ),
                        disabledForegroundColor: AppTheme.ink700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('APPLY RANGE'),
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

  Widget _buildDay(DateTime date) {
    final selectable = _isSelectable(date);
    final isStart = _start != null && DateUtils.isSameDay(date, _start);
    final isEnd = _end != null && DateUtils.isSameDay(date, _end);
    final isBetween =
        _start != null &&
        _end != null &&
        date.isAfter(_start!) &&
        date.isBefore(_end!);
    final isToday = DateUtils.isSameDay(
      date,
      DateUtils.dateOnly(DateTime.now()),
    );
    final selected = isStart || isEnd;

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: selected
            ? AppTheme.ink900
            : isBetween
            ? AppTheme.greenNeon.withValues(alpha: 0.25)
            : Colors.transparent,
        shape: selected ? const CircleBorder() : const RoundedRectangleBorder(),
        child: InkWell(
          onTap: selectable ? () => _selectDate(date) : null,
          customBorder: selected ? const CircleBorder() : null,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: selected ? BoxShape.circle : BoxShape.rectangle,
              border: isToday && !selected
                  ? Border.all(color: AppTheme.greenDark, width: 1)
                  : null,
            ),
            child: Text(
              '${date.day}',
              style: AppTheme.bodyBold(
                size: 12,
                color: !selectable
                    ? AppTheme.ink700.withValues(alpha: 0.32)
                    : selected
                    ? AppTheme.limeYellow
                    : AppTheme.ink900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RangeDateLabel extends StatelessWidget {
  final String label;
  final DateTime? date;
  final bool alignEnd;

  const _RangeDateLabel({
    required this.label,
    required this.date,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.label(size: 8, color: AppTheme.greenDark)),
        const SizedBox(height: 2),
        Text(
          date == null ? 'Select date' : DateFormat('d MMM yyyy').format(date!),
          style: AppTheme.bodyBold(size: 11, color: AppTheme.ink900),
        ),
      ],
    );
  }
}
