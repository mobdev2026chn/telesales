import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/call_log_model.dart';
import '../providers/tele_provider.dart';
import '../theme/app_theme.dart';
import 'book_demo_sheet.dart';

/// Wraps the app: when a call ends (any call, not only dialing sessions) it shows a pop-up
/// offering to book a demo for that client. [navigatorKey] is the app's root navigator.
class PostCallDemoPrompt extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const PostCallDemoPrompt({super.key, required this.child, required this.navigatorKey});

  @override
  State<PostCallDemoPrompt> createState() => _PostCallDemoPromptState();
}

class _PostCallDemoPromptState extends State<PostCallDemoPrompt> {
  TeleProvider? _tele;
  bool _showing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tele = Provider.of<TeleProvider>(context, listen: false);
    if (!identical(tele, _tele)) {
      _tele?.removeListener(_onChanged);
      _tele = tele..addListener(_onChanged);
      _onChanged();
    }
  }

  @override
  void dispose() {
    _tele?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final call = _tele?.pendingDemoPromptCall;
    if (call == null || _showing) return;
    _showing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _show(call));
  }

  Future<void> _show(CallLogModel call) async {
    final tele = _tele;
    final ctx = widget.navigatorKey.currentContext;
    if (tele == null || ctx == null || !mounted) {
      _showing = false;
      return;
    }
    tele.clearDemoPrompt();
    final lead = tele.leadForCall(call);
    final wantsDemo = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dCtx) => _PromptDialog(call: call, displayName: lead.name),
    );
    if (wantsDemo == true) {
      final formCtx = widget.navigatorKey.currentContext;
      if (formCtx != null && formCtx.mounted) {
        final messenger = ScaffoldMessenger.maybeOf(formCtx);
        String bookedName = lead.name;
        final bookedAt = await showBookDemoSheet(
          formCtx,
          lead: lead,
          agentName: tele.callerName,
          onBooked: (name) => bookedName = name,
        );
        if (bookedAt != null) {
          await tele.markDemoBooked(lead, bookedAt, bookedName);
          messenger?.showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.ink900,
              content: Text(
                'Demo booked for ${DateFormat('d MMM · h:mm a').format(bookedAt).toUpperCase()}',
                style: AppTheme.bodyBold(size: 12, color: AppTheme.limeYellow),
              ),
            ),
          );
        }
      }
    }
    _showing = false;
    // Another call may have ended meanwhile
    if (mounted && _tele?.pendingDemoPromptCall != null) _onChanged();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _PromptDialog extends StatelessWidget {
  final CallLogModel call;
  final String displayName;

  const _PromptDialog({required this.call, required this.displayName});

  @override
  Widget build(BuildContext context) {
    final name = displayName.trim().isNotEmpty ? displayName.trim() : 'Unknown caller';
    final talk = call.duration.inSeconds > 0 ? call.durationFormatted.toUpperCase() : '—';
    final direction = call.type == CallType.outgoing ? 'OUTGOING' : 'INCOMING';
    return Dialog(
      backgroundColor: AppTheme.paper,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.ink900, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CALL ENDED · $direction · TALK $talk', style: AppTheme.mono(size: 10.5, color: AppTheme.greenDark, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('BOOK A DEMO?', style: AppTheme.headline(size: 28, color: AppTheme.ink900)),
            const SizedBox(height: 6),
            Text(name, style: AppTheme.bodyBold(size: 15, color: AppTheme.ink900)),
            Text(call.phoneNumber, style: AppTheme.mono(size: 12, color: AppTheme.ink700)),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(true),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: AppTheme.greenNeon,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppTheme.ink900, width: 1.5),
                  boxShadow: AppTheme.neoShadow(color: AppTheme.ink900, offset: 4),
                ),
                child: Center(
                  child: Text('BOOK DEMO →', style: AppTheme.label(size: 11.5, color: AppTheme.ink900, letterSpacing: 0.15)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(false),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppTheme.ink900, width: 1.5),
                ),
                child: Center(
                  child: Text('NOT NOW', style: AppTheme.label(size: 10.5, color: AppTheme.ink900, letterSpacing: 0.12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
