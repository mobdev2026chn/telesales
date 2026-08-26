import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../models/employee_model.dart';
import '../../models/call_log_model.dart';
import '../../providers/tele_provider.dart';

class EmployeeDetailScreen extends StatelessWidget {
  final EmployeeModel employee;
  final VoidCallback onBack;

  const EmployeeDetailScreen({
    super.key,
    required this.employee,
    required this.onBack,
  });

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('d MMM · h:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);
    
    // Get actual real calls for this caller (or all tracked calls on this device)
    final List<CallLogModel> realCalls = tele.simTrackedCallLogs.isNotEmpty
        ? tele.simTrackedCallLogs
        : tele.allCallLogs;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onBack,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_back, size: 16, color: AppTheme.greenDark),
                  const SizedBox(width: 6),
                  Text(
                    'LEADERBOARD',
                    style: AppTheme.label(size: 11, color: AppTheme.greenDark, letterSpacing: 0.14),
                  ),
                ],
              ),
            ),
          ),

          // Employee Header Card
          NeoCard(
            backgroundColor: AppTheme.ink900,
            shadowColor: AppTheme.ink900,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CALLER · ${employee.phone.isNotEmpty ? employee.phone : tele.verifiedTrackingNumber}',
                  style: AppTheme.label(size: 9, color: AppTheme.limeYellow, letterSpacing: 0.18),
                ),
                const SizedBox(height: 6),
                Text(
                  employee.name.toUpperCase(),
                  style: AppTheme.headline(size: 28, color: AppTheme.paper),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _StatCol(value: '${employee.totalCalls}', label: 'CALLS'),
                    const SizedBox(width: 24),
                    _StatCol(
                      value: '${employee.connectedCalls}',
                      label: 'CONNECTED',
                      valueColor: AppTheme.greenGrass,
                    ),
                    const SizedBox(width: 24),
                    _StatCol(
                      value: employee.talkTimeFormatted,
                      label: 'TALK TIME',
                      valueColor: AppTheme.limeYellow,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Call Breakdown Card
          NeoCard(
            backgroundColor: AppTheme.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CALL BREAKDOWN',
                  style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.18),
                ),
                const SizedBox(height: 12),
                _BreakdownRow(label: 'Connected calls', value: '${employee.connectedCalls}', color: AppTheme.greenDark),
                _BreakdownRow(label: 'Incoming answered', value: '${employee.incomingCalls}', color: AppTheme.greenDark),
                _BreakdownRow(label: 'Outgoing dials', value: '${employee.outgoingCalls}', color: AppTheme.ink900),
                _BreakdownRow(label: 'Missed calls', value: '${employee.missedCalls}', color: AppTheme.redMissed),
                _BreakdownRow(label: 'Never attended', value: '${employee.neverAttendedCalls}', color: AppTheme.muted),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Real Live Recent Calls Card
          NeoCard(
            backgroundColor: AppTheme.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'RECENT CALLS (${realCalls.length})',
                      style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.18),
                    ),
                    Text(
                      'REAL TIME',
                      style: AppTheme.mono(size: 9, color: AppTheme.greenDark),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (realCalls.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(Icons.phone_disabled, size: 30, color: AppTheme.muted),
                          const SizedBox(height: 8),
                          Text(
                            'No calls logged for this caller yet.',
                            style: AppTheme.bodyBold(size: 12, color: AppTheme.ink900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Calls made or received will appear here live.',
                            style: AppTheme.body(size: 11, color: AppTheme.muted),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: realCalls.take(15).length,
                    separatorBuilder: (context, index) => const Divider(color: AppTheme.paper, height: 16),
                    itemBuilder: (context, index) {
                      final call = realCalls[index];
                      final typeColor = call.type == CallType.incoming
                          ? AppTheme.greenDark
                          : call.type == CallType.missed
                              ? AppTheme.redMissed
                              : AppTheme.ink900;

                      return _RealCallRow(
                        call: call,
                        timeAgo: _formatRelativeTime(call.timestamp),
                        typeColor: typeColor,
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCol extends StatelessWidget {
  final String value;
  final String label;
  final Color valueColor;

  const _StatCol({required this.value, required this.label, this.valueColor = AppTheme.paper});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppTheme.headline(size: 24, color: valueColor)),
        Text(label, style: AppTheme.label(size: 9, color: AppTheme.lightMuted, letterSpacing: 0.14)),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _BreakdownRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.paper, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTheme.bodyBold(size: 12, color: color)),
          Text(value, style: AppTheme.mono(size: 12, color: AppTheme.ink900)),
        ],
      ),
    );
  }
}

class _RealCallRow extends StatelessWidget {
  final CallLogModel call;
  final String timeAgo;
  final Color typeColor;

  const _RealCallRow({
    required this.call,
    required this.timeAgo,
    required this.typeColor,
  });

  @override
  Widget build(BuildContext context) {
    final durStr = call.duration.inSeconds > 0
        ? (call.duration.inMinutes > 0
            ? '${call.duration.inMinutes}m ${call.duration.inSeconds % 60}s'
            : '${call.duration.inSeconds}s')
        : '0s';

    final displayName = call.contactName.isNotEmpty && call.contactName != 'Unknown'
        ? call.contactName
        : (call.phoneNumber.isNotEmpty ? call.phoneNumber : 'Unknown Client');

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                style: AppTheme.bodyBold(size: 13, color: AppTheme.ink900),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '$timeAgo · ${call.phoneNumber}',
                style: AppTheme.mono(size: 10, color: AppTheme.muted),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              call.type.name.toUpperCase(),
              style: AppTheme.label(size: 9, color: typeColor, letterSpacing: 0.1),
            ),
            const SizedBox(height: 2),
            Text(
              durStr,
              style: AppTheme.mono(size: 11, color: AppTheme.ink900),
            ),
          ],
        ),
      ],
    );
  }
}
