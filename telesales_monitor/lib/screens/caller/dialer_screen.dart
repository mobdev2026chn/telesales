import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../providers/tele_provider.dart';

/// Phase 1: Custom Dial Pad Screen
/// Allows callers to type phone numbers using an on-screen keypad and initiate
/// a phone call via the Android system dialer using the `tel:` URI scheme.
class DialerScreen extends StatefulWidget {
  const DialerScreen({super.key});

  @override
  State<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends State<DialerScreen> {
  String _dialedNumber = '';

  // Appends a digit or character to the current dialed number
  void _onKeyPress(String char) {
    if (_dialedNumber.length < 20) {
      setState(() {
        _dialedNumber += char;
      });
    }
  }

  // Deletes the last digit (backspace)
  void _onBackspace() {
    if (_dialedNumber.isNotEmpty) {
      setState(() {
        _dialedNumber = _dialedNumber.substring(0, _dialedNumber.length - 1);
      });
    }
  }

  // Clears the entire number (on clear button or long-press backspace)
  void _onClear() {
    if (_dialedNumber.isNotEmpty) {
      setState(() {
        _dialedNumber = '';
      });
    }
  }

  // Initiates the phone call using url_launcher (tel: URI)
  Future<void> _makeCall() async {
    final clean = _dialedNumber.trim();
    if (clean.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.ink900,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Text(
            'Please enter a phone number to call',
            style: AppTheme.bodyBold(size: 12, color: AppTheme.limeYellow),
          ),
        ),
      );
      return;
    }

    final Uri phoneUri = Uri(scheme: 'tel', path: clean);
    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback to TeleProvider's direct dialer if canLaunchUrl check behaves strictly
        if (mounted) {
          final tele = Provider.of<TeleProvider>(context, listen: false);
          await tele.makeDirectCall(clean);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.redMissed,
            content: Text(
              'Could not launch dialer: $e',
              style: AppTheme.bodyBold(size: 12, color: AppTheme.white),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);
    final sims = tele.detectedSims;
    final hasDualSim = sims.length > 1;

    // Standard phone keypad data: (Number, Subtitle/Letters)
    const keypadKeys = [
      [('1', ''), ('2', 'ABC'), ('3', 'DEF')],
      [('4', 'GHI'), ('5', 'JKL'), ('6', 'MNO')],
      [('7', 'PQRS'), ('8', 'TUV'), ('9', 'WXYZ')],
      [('*', ''), ('0', '+'), ('#', '')],
    ];

    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ASKEVA · DIALER',
                        style: AppTheme.mono(size: 10, color: AppTheme.muted, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'CUSTOM KEYPAD',
                        style: AppTheme.headline(size: 26, color: AppTheme.ink900),
                      ),
                    ],
                  ),
                  if (hasDualSim)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.ink900, width: 1.2),
                      ),
                      child: Text(
                        'WORK SIM: ${tele.workSimSlotIndex + 1}',
                        style: AppTheme.label(size: 9, color: AppTheme.greenDark),
                      ),
                    ),
                ],
              ),

              const Spacer(flex: 1),

              // Phone Number Display Container
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.ink900, width: 1.5),
                  boxShadow: AppTheme.neoShadowSm(color: AppTheme.ink900),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true, // Auto-scroll to end as user types
                        child: Text(
                          _dialedNumber.isEmpty ? 'Enter number…' : _dialedNumber,
                          style: _dialedNumber.isEmpty
                              ? AppTheme.mono(size: 22, color: AppTheme.ink700.withValues(alpha: 0.4))
                              : AppTheme.mono(size: 24, color: AppTheme.ink900, weight: FontWeight.w700),
                          maxLines: 1,
                        ),
                      ),
                    ),
                    if (_dialedNumber.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      // Backspace Button (Tap = 1 digit, Long-press = clear all)
                      GestureDetector(
                        onTap: _onBackspace,
                        onLongPress: _onClear,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.paper,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.ink900, width: 1),
                          ),
                          child: const Icon(
                            Icons.backspace_outlined,
                            size: 18,
                            color: AppTheme.ink900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const Spacer(flex: 1),

              // Keypad Grid (0-9, *, #)
              Column(
                children: keypadKeys.map((row) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: row.map((keyInfo) {
                        final digit = keyInfo.$1;
                        final letters = keyInfo.$2;
                        return _KeypadButton(
                          digit: digit,
                          letters: letters,
                          onTap: () => _onKeyPress(digit),
                          onLongPress: digit == '0' ? () => _onKeyPress('+') : null,
                        );
                      }).toList(),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 12),

              // Bottom Actions Row (Clear | CALL BUTTON | Backspace)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Left Action: Clear All
                  SizedBox(
                    width: 64,
                    height: 48,
                    child: _dialedNumber.isNotEmpty
                        ? TextButton(
                            onPressed: _onClear,
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.ink900,
                            ),
                            child: Text(
                              'CLEAR',
                              style: AppTheme.label(size: 10, color: AppTheme.muted),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),

                  // Center Big Call Button
                  GestureDetector(
                    onTap: _makeCall,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: AppTheme.greenNeon,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.ink900, width: 2),
                        boxShadow: AppTheme.neoShadow(color: AppTheme.ink900, offset: 4),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.phone_rounded,
                          color: AppTheme.ink900,
                          size: 32,
                        ),
                      ),
                    ),
                  ),

                  // Right Action: Backspace
                  SizedBox(
                    width: 64,
                    height: 48,
                    child: _dialedNumber.isNotEmpty
                        ? IconButton(
                            onPressed: _onBackspace,
                            icon: const Icon(
                              Icons.backspace_rounded,
                              color: AppTheme.ink900,
                              size: 22,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),

              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single interactive keypad button widget matching AskEVA's neo-brutalist theme
class _KeypadButton extends StatefulWidget {
  final String digit;
  final String letters;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _KeypadButton({
    required this.digit,
    required this.letters,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_KeypadButton> createState() => _KeypadButtonState();
}

class _KeypadButtonState extends State<_KeypadButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: 78,
        height: 60,
        transform: _isPressed ? Matrix4.translationValues(2, 2, 0) : Matrix4.identity(),
        decoration: BoxDecoration(
          color: _isPressed ? AppTheme.limeYellow : AppTheme.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.ink900, width: 1.5),
          boxShadow: _isPressed
              ? null
              : AppTheme.neoShadowSm(color: AppTheme.ink900),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.digit,
              style: AppTheme.headline(size: 24, color: AppTheme.ink900),
            ),
            if (widget.letters.isNotEmpty)
              Text(
                widget.letters,
                style: AppTheme.label(size: 8.5, color: AppTheme.muted, letterSpacing: 0.12),
              ),
          ],
        ),
      ),
    );
  }
}
