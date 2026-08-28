import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/tele_provider.dart';

class DialerPadSheet extends StatefulWidget {
  const DialerPadSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const DialerPadSheet(),
    );
  }

  @override
  State<DialerPadSheet> createState() => _DialerPadSheetState();
}

class _DialerPadSheetState extends State<DialerPadSheet> {
  String _dialedNumber = '';

  void _onKeyPress(String digit) {
    if (_dialedNumber.length < 15) {
      setState(() {
        _dialedNumber += digit;
      });
    }
  }

  void _onBackspace() {
    if (_dialedNumber.isNotEmpty) {
      setState(() {
        _dialedNumber = _dialedNumber.substring(0, _dialedNumber.length - 1);
      });
    }
  }

  void _onClear() {
    setState(() {
      _dialedNumber = '';
    });
  }

  int _selectedSimSlot = 0;

  void _makeCall() {
    if (_dialedNumber.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.ink900,
          content: Text(
            'Please enter a phone number to dial',
            style: AppTheme.body(size: 12, color: AppTheme.limeYellow),
          ),
        ),
      );
      return;
    }
    final phone = _dialedNumber.trim();
    Navigator.of(context).pop();
    final tele = Provider.of<TeleProvider>(context, listen: false);
    tele.makeDirectCall(phone, slot: _selectedSimSlot);
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context, listen: false);
    final sims = tele.detectedSims;
    final hasDualSim = sims.length > 1;

    final keyValues = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['*', '0', '#'],
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: const BoxDecoration(
        color: AppTheme.ink900,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Top Header Row (Backspace & Close)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_dialedNumber.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.backspace_outlined, color: AppTheme.white, size: 20),
                  onPressed: _onBackspace,
                ),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: AppTheme.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 16, color: AppTheme.ink900),
                ),
              ),
            ],
          ),

          // Display Dialed Number
          if (_dialedNumber.isNotEmpty) ...[
            Text(
              _dialedNumber,
              style: AppTheme.mono(size: 26, color: AppTheme.limeYellow),
            ),
            const SizedBox(height: 16),
          ] else ...[
            const SizedBox(height: 12),
          ],

          // Keypad Grid
          Column(
            children: keyValues.map((row) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: row.map((key) {
                    return GestureDetector(
                      onTap: () => _onKeyPress(key),
                      child: Container(
                        width: 72,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppTheme.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.white.withValues(alpha: 0.15), width: 1),
                        ),
                        child: Center(
                          child: Text(
                            key,
                            style: AppTheme.mono(size: 20, color: AppTheme.white),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Bottom Action Controls (CLEAR | 📞 CALL | SIM 1/2 Toggle)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              GestureDetector(
                onTap: _onClear,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppTheme.white.withValues(alpha: 0.2), width: 1),
                  ),
                  child: Text(
                    'CLEAR',
                    style: AppTheme.label(size: 9, color: AppTheme.white),
                  ),
                ),
              ),
              GestureDetector(
                onTap: _makeCall,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppTheme.greenNeon,
                    shape: BoxShape.circle,
                    boxShadow: AppTheme.neoShadow(color: AppTheme.limeYellow, offset: 3),
                  ),
                  child: const Icon(
                    Icons.phone_in_talk_rounded,
                    color: AppTheme.ink900,
                    size: 28,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  if (hasDualSim) {
                    setState(() {
                      _selectedSimSlot = _selectedSimSlot == 0 ? 1 : 0;
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppTheme.greenNeon, width: 1),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'SIM ${_selectedSimSlot + 1}',
                        style: AppTheme.label(size: 9, color: AppTheme.greenNeon),
                      ),
                      if (hasDualSim) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.swap_horiz, size: 14, color: AppTheme.greenNeon),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
