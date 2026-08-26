import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../widgets/neo_button.dart';
import '../../providers/tele_provider.dart';
import '../../models/call_log_model.dart';

class CallerHistoryScreen extends StatefulWidget {
  const CallerHistoryScreen({super.key});

  @override
  State<CallerHistoryScreen> createState() => _CallerHistoryScreenState();
}

class _CallerHistoryScreenState extends State<CallerHistoryScreen> {
  void _showDialpadSheet(BuildContext context, TeleProvider tele) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _InbuildDialpadSheet(tele: tele);
      },
    );
  }

  void _showNoteDialog(BuildContext context, CallLogModel call, TeleProvider tele) {
    final noteCtrl = TextEditingController(text: call.note ?? '');
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: NeoCard(
            backgroundColor: AppTheme.white,
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ADD NOTE & LEAD TAG', style: AppTheme.label(size: 10, color: AppTheme.muted)),
                const SizedBox(height: 6),
                Text(call.contactName, style: AppTheme.headline(size: 20)),
                Text(call.phoneNumber, style: AppTheme.mono(size: 12, color: AppTheme.ink700)),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.paper,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.ink900, width: 1),
                  ),
                  child: TextField(
                    controller: noteCtrl,
                    maxLines: 3,
                    style: AppTheme.body(size: 13),
                    decoration: const InputDecoration(
                      hintText: 'Enter lead notes, deal size, or callback time...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Cancel', style: AppTheme.bodyBold(size: 12, color: AppTheme.muted)),
                    ),
                    const SizedBox(width: 8),
                    NeoButton.pill(
                      backgroundColor: AppTheme.ink900,
                      onTap: () {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppTheme.ink900,
                            content: Text('Note updated for ${call.contactName}', style: AppTheme.bodyBold(size: 12, color: AppTheme.white)),
                          ),
                        );
                      },
                      child: Text('SAVE NOTE', style: AppTheme.label(size: 10, color: AppTheme.limeYellow)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);

    final logs = tele.filteredCallLogs;

    final filterOptions = [
      {'label': 'ALL', 'filter': 'ALL'},
      {'label': 'INCOMING', 'filter': 'INCOMING'},
      {'label': 'OUTGOING', 'filter': 'OUTGOING'},
      {'label': 'MISSED', 'filter': 'MISSED'},
      {'label': 'REJECTED', 'filter': 'REJECTED'},
    ];

    final currentDateStr = DateFormat('d MMM yyyy').format(DateTime.now()).toUpperCase();
    final callerLabel = tele.verifiedTrackingNumber.isNotEmpty ? tele.verifiedTrackingNumber : 'PRIYANKA';

    return Scaffold(
      backgroundColor: AppTheme.paper,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: FloatingActionButton(
          backgroundColor: AppTheme.ink900,
          foregroundColor: AppTheme.limeYellow,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppTheme.ink900, width: 1.5),
          ),
          onPressed: () => _showDialpadSheet(context, tele),
          child: const Icon(Icons.dialpad, size: 26),
        ),
      ),
      body: RefreshIndicator(
        color: AppTheme.greenNeon,
        backgroundColor: AppTheme.ink900,
        onRefresh: () async {
          await tele.fetchDeviceCallLogs();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Header Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'CALL HISTORY',
                            style: AppTheme.headline(size: 30, color: AppTheme.ink900),
                          ),
                          Text(
                            '.',
                            style: AppTheme.headline(size: 30, color: AppTheme.greenNeon),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ASKEVA · $callerLabel · $currentDateStr',
                        style: AppTheme.mono(size: 10, color: AppTheme.muted),
                      ),
                    ],
                  ),
                  NeoButton.pill(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    onTap: () => tele.logout(),
                    child: Row(
                      children: [
                        Text(
                          'CALLER',
                          style: AppTheme.label(size: 9, color: AppTheme.ink900, letterSpacing: 0.12),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.close, size: 12, color: AppTheme.ink900),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Filter Pills Row
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: filterOptions.map((opt) {
                    final isSel = tele.callFilter == opt['filter'];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => tele.setCallFilter(opt['filter'] as String),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSel ? AppTheme.ink900 : AppTheme.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppTheme.ink900, width: 1.5),
                            boxShadow: isSel ? AppTheme.neoShadowSm(color: AppTheme.ink900) : null,
                          ),
                          child: Text(
                            opt['label'] as String,
                            style: AppTheme.label(
                              size: 11,
                              color: isSel ? AppTheme.white : AppTheme.ink900,
                              letterSpacing: 0.12,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 14),

              // Call Log Cards List
              if (logs.isEmpty) ...[
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(Icons.phone_missed, size: 44, color: AppTheme.muted),
                        const SizedBox(height: 10),
                        Text('NO LOGGED CALLS', style: AppTheme.headline(size: 18)),
                        const SizedBox(height: 4),
                        Text(
                          'Pull down to refresh real phone calls.',
                          style: AppTheme.body(size: 12, color: AppTheme.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: logs.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) {
                    final call = logs[i];
                    return _NeoCallCard(
                      call: call,
                      tele: tele,
                      onAddNote: () => _showNoteDialog(context, call, tele),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NeoCallCard extends StatelessWidget {
  final CallLogModel call;
  final TeleProvider tele;
  final VoidCallback onAddNote;

  const _NeoCallCard({
    required this.call,
    required this.tele,
    required this.onAddNote,
  });

  @override
  Widget build(BuildContext context) {
    String typeLabel = '↑ Outgoing';
    Color typeColor = const Color(0xFFD97706);

    if (call.type == CallType.incoming) {
      typeLabel = '↓ Incoming';
      typeColor = const Color(0xFF059669);
    } else if (call.type == CallType.missed) {
      typeLabel = '↩ Missed';
      typeColor = const Color(0xFFDC2626);
    } else if (call.type == CallType.rejected || call.type == CallType.neverAttended) {
      typeLabel = '⊘ Rejected';
      typeColor = const Color(0xFFDC2626);
    }

    final timeStr = DateFormat('h:mm a').format(call.timestamp);
    final durationStr = call.duration.inSeconds > 0 ? call.durationFormatted : '—';

    return NeoCard(
      backgroundColor: AppTheme.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Contact Name + Call Type
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  call.contactName,
                  style: AppTheme.bodyBold(size: 16, color: AppTheme.ink900),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                typeLabel,
                style: AppTheme.bodyBold(size: 12, color: typeColor),
              ),
            ],
          ),
          const SizedBox(height: 3),

          // Second Row: Phone Number + Time & Duration
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                call.phoneNumber,
                style: AppTheme.mono(size: 12, color: AppTheme.ink700),
              ),
              Text(
                '$timeStr · $durationStr',
                style: AppTheme.mono(size: 11, color: AppTheme.ink700),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Note / Tag Bar
          GestureDetector(
            onTap: onAddNote,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFECE6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.ink900.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_note, size: 16, color: AppTheme.ink700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      (call.note != null && call.note!.isNotEmpty)
                          ? call.note!
                          : 'Tap to add note & tag...',
                      style: AppTheme.body(size: 12, color: AppTheme.ink700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Action Buttons (Copy, SMS, WhatsApp, Direct Call)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _ActionMiniBtn(
                icon: Icons.copy_outlined,
                tooltip: 'Copy',
                color: AppTheme.muted,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: call.phoneNumber));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppTheme.ink900,
                      duration: const Duration(seconds: 1),
                      content: Text('Copied ${call.phoneNumber}', style: AppTheme.bodyBold(size: 12, color: AppTheme.white)),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              _ActionMiniBtn(
                icon: Icons.chat_bubble_outline,
                tooltip: 'SMS',
                color: const Color(0xFF0284C7),
                onTap: () => tele.launchSms(call.phoneNumber),
              ),
              const SizedBox(width: 8),
              _ActionMiniBtn(
                customIcon: const _WhatsAppIcon(size: 16, color: Color(0xFF25D366)),
                tooltip: 'WhatsApp',
                color: const Color(0xFF25D366),
                onTap: () => tele.launchWhatsApp(call.phoneNumber),
              ),
              const SizedBox(width: 8),
              _ActionMiniBtn(
                icon: Icons.phone_outlined,
                tooltip: 'Call',
                color: AppTheme.greenDark,
                onTap: () => tele.launchCall(call.phoneNumber),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionMiniBtn extends StatelessWidget {
  final IconData? icon;
  final Widget? customIcon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _ActionMiniBtn({
    this.icon,
    this.customIcon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTheme.ink900, width: 1),
          ),
          child: customIcon ?? Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

class _WhatsAppIcon extends StatelessWidget {
  final double size;
  final Color color;

  const _WhatsAppIcon({
    this.size = 16,
    this.color = const Color(0xFF25D366),
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _WhatsAppPainter(color: color),
    );
  }
}

class _WhatsAppPainter extends CustomPainter {
  final Color color;
  const _WhatsAppPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;
    final r = w * 0.42;
    final cx = w * 0.5;
    final cy = h * 0.46;

    // Draw speech bubble with tail
    final path = Path();
    path.addArc(Rect.fromCircle(center: Offset(cx, cy), radius: r), 0.75 * 3.14159, 1.8 * 3.14159);
    path.lineTo(w * 0.12, h * 0.90);
    path.lineTo(w * 0.32, h * 0.80);
    path.close();

    canvas.drawPath(path, strokePaint);

    // Draw telephone handset receiver inside bubble
    final phonePath = Path();
    final px = w * 0.35;
    final py = h * 0.28;
    phonePath.moveTo(px, py + h * 0.08);
    phonePath.cubicTo(px, py, px + w * 0.10, py, px + w * 0.13, py + h * 0.07);
    phonePath.lineTo(px + w * 0.17, py + h * 0.13);
    phonePath.lineTo(px + w * 0.13, py + h * 0.18);
    phonePath.lineTo(px + w * 0.18, py + h * 0.24);
    phonePath.lineTo(px + w * 0.24, py + h * 0.20);
    phonePath.lineTo(px + w * 0.30, py + h * 0.24);
    phonePath.cubicTo(px + w * 0.32, py + h * 0.31, px + w * 0.24, py + h * 0.36, px + w * 0.17, py + h * 0.32);
    phonePath.cubicTo(px + w * 0.07, py + h * 0.26, px, py + h * 0.17, px, py + h * 0.08);
    phonePath.close();

    canvas.drawPath(phonePath, fillPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _InbuildDialpadSheet extends StatefulWidget {
  final TeleProvider tele;
  const _InbuildDialpadSheet({required this.tele});

  @override
  State<_InbuildDialpadSheet> createState() => _InbuildDialpadSheetState();
}

class _InbuildDialpadSheetState extends State<_InbuildDialpadSheet> {
  String _digits = '';
  int _selectedSim = 0;

  void _append(String d) {
    setState(() {
      _digits += d;
    });
  }

  void _backspace() {
    if (_digits.isNotEmpty) {
      setState(() {
        _digits = _digits.substring(0, _digits.length - 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: AppTheme.ink900, width: 2),
        boxShadow: AppTheme.neoShadow(),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.ink900.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),

          // Top Bar with Close & SIM Toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('INBUILD PHONE DIALER', style: AppTheme.label(size: 10, color: AppTheme.muted)),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _selectedSim = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _selectedSim == 0 ? AppTheme.greenNeon : AppTheme.paper,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.ink900, width: 1),
                      ),
                      child: Text('SIM 1', style: AppTheme.label(size: 9, color: AppTheme.ink900)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => setState(() => _selectedSim = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _selectedSim == 1 ? AppTheme.orangePill : AppTheme.paper,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.ink900, width: 1),
                      ),
                      child: Text('SIM 2', style: AppTheme.label(size: 9, color: _selectedSim == 1 ? AppTheme.white : AppTheme.ink900)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.ink900, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Digits Display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.paper,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.ink900, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _digits.isEmpty ? 'Dial a number...' : _digits,
                    style: AppTheme.mono(
                      size: _digits.length > 12 ? 18 : 24,
                      color: _digits.isEmpty ? AppTheme.muted : AppTheme.ink900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_digits.isNotEmpty)
                  GestureDetector(
                    onTap: _backspace,
                    onLongPress: () => setState(() => _digits = ''),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.backspace_outlined, size: 22, color: AppTheme.ink900),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Keypad Matrix
          _buildKeypadRow(['1', '2', '3'], ['', 'ABC', 'DEF']),
          const SizedBox(height: 10),
          _buildKeypadRow(['4', '5', '6'], ['GHI', 'JKL', 'MNO']),
          const SizedBox(height: 10),
          _buildKeypadRow(['7', '8', '9'], ['PQRS', 'TUV', 'WXYZ']),
          const SizedBox(height: 10),
          _buildKeypadRow(['*', '0', '#'], ['', '+', '']),
          const SizedBox(height: 18),

          // Call Action Button
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () {
                  if (_digits.isNotEmpty) {
                    widget.tele.makeDirectCall(_digits, slot: _selectedSim);
                    Navigator.pop(context);
                  }
                },
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: AppTheme.greenDark,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.ink900, width: 2),
                    boxShadow: AppTheme.neoShadow(),
                  ),
                  child: const Icon(Icons.phone, color: AppTheme.white, size: 32),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeypadRow(List<String> digits, List<String> letters) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (int i = 0; i < digits.length; i++)
          _buildKeypadBtn(digits[i], letters[i]),
      ],
    );
  }

  Widget _buildKeypadBtn(String digit, String letters) {
    return GestureDetector(
      onTap: () => _append(digit),
      onLongPress: () {
        if (digit == '0') _append('+');
      },
      child: Container(
        width: 72,
        height: 52,
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.ink900, width: 1.2),
          boxShadow: AppTheme.neoShadowSm(),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(digit, style: AppTheme.headline(size: 20, color: AppTheme.ink900)),
            if (letters.isNotEmpty)
              Text(letters, style: AppTheme.mono(size: 8, color: AppTheme.muted)),
          ],
        ),
      ),
    );
  }
}
