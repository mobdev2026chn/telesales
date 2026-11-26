import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/tele_provider.dart';
import '../../services/dialer_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';

/// AskEVA's call screen while it is the phone's Phone app: incoming (Answer / Decline), calling,
/// ongoing (timer, mute, loudspeaker, keypad, hold, end), call waiting and the dual-SIM picker.
/// Driven by [call] (the native CallManager's events); back / the chevron only hides it, the call goes on.
/// Same look as the rest of the app: paper background, white cards with ink borders and offset shadows.
class InCallScreen extends StatefulWidget {
  const InCallScreen({super.key, required this.call, required this.onMinimize});

  final ValueListenable<CallEvent?> call;
  final VoidCallback onMinimize;

  @override
  State<InCallScreen> createState() => _InCallScreenState();
}

class _InCallScreenState extends State<InCallScreen> {
  final _dialer = DialerService.instance;
  Timer? _ticker;
  bool _keypad = false;
  String _keysTyped = '';

  @override
  void initState() {
    super.initState();
    // The talk timer
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.call.value?.state == CallState.active) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _key(String digit) async {
    setState(() {
      final typed = _keysTyped + digit;
      _keysTyped = typed.length > 24 ? typed.substring(typed.length - 24) : typed;
    });
    await _dialer.playDtmf(digit);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await _dialer.stopDtmf();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: SafeArea(
        child: ValueListenableBuilder<CallEvent?>(
          valueListenable: widget.call,
          builder: (context, e, _) {
            if (e == null || !e.isLive) {
              return Center(
                child: Text('CALL ENDED', style: AppTheme.headline(size: 26, color: AppTheme.ink900)),
              );
            }
            return _body(context, e);
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context, CallEvent e) {
    final lead = context.read<TeleProvider>().callerNameFor(e.phoneNumber);
    final name = lead ??
        (e.displayName.trim().isNotEmpty ? e.displayName.trim() : (e.phoneNumber.isEmpty ? 'Unknown number' : e.phoneNumber));
    final showNumber = e.phoneNumber.isNotEmpty && name != e.phoneNumber;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      child: Column(
        children: [
          // Header, like the other tabs: small mono label + big Anton title
          Row(
            children: [
              _squareButton(
                icon: Icons.keyboard_arrow_down_rounded,
                tooltip: 'Back to AskEVA (the call goes on)',
                onTap: widget.onMinimize,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ASKEVA · CALL', style: AppTheme.mono(size: 10, color: AppTheme.muted, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      e.isRingingIn ? 'INCOMING CALL' : (e.isIncoming ? 'INCOMING' : 'OUTGOING'),
                      style: AppTheme.headline(size: 24, color: AppTheme.ink900),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(flex: 2),
          _callerCard(e, name, showNumber, isLead: lead != null),
          if (e.heldCalls > 0 && !e.isRingingIn) ...[
            const SizedBox(height: 14),
            _pill(
              e.heldCalls == 1 ? '1 CALL ON HOLD · SWAP' : '${e.heldCalls} CALLS ON HOLD · SWAP',
              Icons.swap_calls_rounded,
              _dialer.swapCalls,
            ),
          ] else if (e.otherCalls > 0 && e.isRingingIn) ...[
            const SizedBox(height: 14),
            Text('Answering puts your current call on hold', style: AppTheme.body(size: 12, color: AppTheme.ink700)),
          ],
          const Spacer(flex: 3),
          if (e.state == CallState.selectSim)
            _simPicker(e)
          else if (e.isRingingIn)
            _incomingButtons()
          else ...[
            if (_keypad) _dtmfPad() else _controls(e),
            const SizedBox(height: 24),
            _roundButton(
              color: AppTheme.redMissed,
              icon: Icons.call_end_rounded,
              iconColor: AppTheme.white,
              label: 'END',
              onTap: _dialer.endCall,
            ),
          ],
        ],
      ),
    );
  }

  /// White neo card: avatar, name, number, LEAD tag and the dark status pill (timer).
  Widget _callerCard(CallEvent e, String name, bool showNumber, {required bool isLead}) {
    return NeoCard(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.limeYellow,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.ink900, width: 2),
                boxShadow: AppTheme.neoShadowSm(),
              ),
              child: Text(_initials(name), style: AppTheme.headline(size: 30, color: AppTheme.ink900)),
            ),
            const SizedBox(height: 16),
            Text(
              name.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.headline(size: 28, color: AppTheme.ink900),
            ),
            if (showNumber) ...[
              const SizedBox(height: 6),
              Text(e.phoneNumber, style: AppTheme.mono(size: 13, color: AppTheme.ink700)),
            ],
            if (isLead) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.limeYellow,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppTheme.ink900, width: 1.2),
                ),
                child: Text('LEAD', style: AppTheme.label(size: 9, color: AppTheme.ink900)),
              ),
            ],
            const SizedBox(height: 16),
            // Dark pill, like the dashboard's daily-target card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.ink900,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                callStatusText(e, DateTime.now()).toUpperCase(),
                style: AppTheme.mono(size: 15, color: AppTheme.limeYellow, weight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _incomingButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _roundButton(
          color: AppTheme.redMissed,
          icon: Icons.call_end_rounded,
          iconColor: AppTheme.white,
          label: 'DECLINE',
          onTap: _dialer.rejectCall,
        ),
        // Same green button as the Dialer tab's call button
        _roundButton(
          color: AppTheme.greenNeon,
          icon: Icons.phone_rounded,
          iconColor: AppTheme.ink900,
          label: 'ANSWER',
          onTap: _dialer.answerCall,
        ),
      ],
    );
  }

  Widget _controls(CallEvent e) {
    final active = e.state == CallState.active;
    final holding = e.state == CallState.holding;
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _toggle(
              icon: e.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
              label: e.muted ? 'UNMUTE' : 'MUTE',
              on: e.muted,
              onTap: () => _dialer.setMuted(!e.muted),
            ),
            _toggle(
              icon: Icons.volume_up_rounded,
              label: 'SPEAKER',
              on: e.speakerOn,
              onTap: () => _dialer.setSpeaker(!e.speakerOn),
            ),
            _toggle(
              icon: Icons.dialpad_rounded,
              label: 'KEYPAD',
              on: false,
              onTap: active ? () => setState(() => _keypad = true) : null,
            ),
            _toggle(
              icon: holding ? Icons.play_arrow_rounded : Icons.pause_rounded,
              label: holding ? 'RESUME' : 'HOLD',
              on: holding,
              onTap: holding ? _dialer.unholdCall : (active && e.canHold ? _dialer.holdCall : null),
            ),
          ],
        ),
        // Android gives AskEVA the microphone only: the customer is recorded through the loudspeaker
        if (active && !e.speakerOn) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.orangePill, width: 1.4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.volume_off_rounded, size: 16, color: AppTheme.orangePill),
                const SizedBox(width: 8),
                Flexible(
                  child: Text('Speaker off: only your voice is recorded', style: AppTheme.bodyBold(size: 12, color: AppTheme.ink900)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// In-call keypad, styled like the Dialer tab's keypad.
  Widget _dtmfPad() {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['*', '0', '#'],
    ];
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.ink900, width: 1.5),
          ),
          child: Text(
            _keysTyped.isEmpty ? ' ' : _keysTyped,
            textAlign: TextAlign.center,
            style: AppTheme.mono(size: 20, color: AppTheme.ink900, weight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),
        for (final row in keys)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final k in row)
                  GestureDetector(
                    onTap: () => _key(k),
                    child: Container(
                      width: 72,
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.ink900, width: 1.5),
                        boxShadow: AppTheme.neoShadowSm(),
                      ),
                      child: Text(k, style: AppTheme.headline(size: 22, color: AppTheme.ink900)),
                    ),
                  ),
              ],
            ),
          ),
        TextButton(
          onPressed: () => setState(() => _keypad = false),
          child: Text('HIDE KEYPAD', style: AppTheme.label(size: 10, color: AppTheme.ink900)),
        ),
      ],
    );
  }

  Widget _simPicker(CallEvent e) {
    final choices = e.simChoices.isEmpty ? const ['SIM 1', 'SIM 2'] : e.simChoices;
    return Column(
      children: [
        Text('CALL WITH', style: AppTheme.label(size: 10, color: AppTheme.ink900)),
        const SizedBox(height: 10),
        for (var i = 0; i < choices.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _pill(choices[i].toUpperCase(), Icons.sim_card_rounded, () => _dialer.selectSim(i), wide: true),
          ),
        const SizedBox(height: 8),
        _roundButton(
          color: AppTheme.redMissed,
          icon: Icons.call_end_rounded,
          iconColor: AppTheme.white,
          label: 'CANCEL',
          onTap: _dialer.endCall,
        ),
      ],
    );
  }

  /// Mute / Speaker / Keypad / Hold: white rounded squares, lime when on.
  Widget _toggle({required IconData icon, required String label, required bool on, VoidCallback? onTap}) {
    final enabled = onTap != null;
    // Four share the row evenly, so narrow phones never overflow
    return Expanded(
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: on ? AppTheme.limeYellow : AppTheme.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.ink900, width: 1.5),
                  boxShadow: enabled ? AppTheme.neoShadowSm() : null,
                ),
                child: Icon(icon, color: AppTheme.ink900, size: 26),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, maxLines: 1, style: AppTheme.label(size: 9, color: AppTheme.ink900)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Answer / Decline / End: the Dialer tab's round call button (ink border, offset shadow).
  Widget _roundButton({
    required Color color,
    required IconData icon,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.ink900, width: 2),
              boxShadow: AppTheme.neoShadow(offset: 4),
            ),
            child: Icon(icon, color: iconColor, size: 32),
          ),
          const SizedBox(height: 10),
          Text(label, style: AppTheme.label(size: 10, color: AppTheme.ink900)),
        ],
      ),
    );
  }

  Widget _squareButton({required IconData icon, required String tooltip, required VoidCallback onTap}) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.ink900, width: 1.5),
            boxShadow: AppTheme.neoShadowSm(),
          ),
          child: Icon(icon, color: AppTheme.ink900, size: 26),
        ),
      ),
    );
  }

  Widget _pill(String label, IconData icon, VoidCallback onTap, {bool wide = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: wide ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppTheme.ink900, width: 1.5),
          boxShadow: AppTheme.neoShadowSm(),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: AppTheme.ink900),
            const SizedBox(width: 8),
            Text(label, style: AppTheme.label(size: 10, color: AppTheme.ink900)),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty && RegExp(r'[A-Za-z]').hasMatch(w[0]));
    final letters = words.take(2).map((w) => w[0].toUpperCase()).join();
    return letters.isEmpty ? '#' : letters;
  }
}
