// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import '../../providers/tele_provider.dart';
// import '../../theme/app_theme.dart';
// import '../../widgets/neo_card.dart';

// class CallerStatsScreen extends StatelessWidget {
//   const CallerStatsScreen({super.key});

//   @override
//   Widget build(BuildContext context) {
//     final tele = Provider.of<TeleProvider>(context);
//     final repeated = tele.mostRepeatedCallToday;
//     final longest = tele.longestCallToday;
//     final longestName = longest == null
//         ? 'No answered calls today'
//         : (longest.contactName != 'Unknown'
//             ? longest.contactName
//             : longest.phoneNumber);
//     final repeatedName =
//         repeated == null ? 'No repeat calls today' : repeated['name']?.toString() ?? '—';
//     final repeatedCount =
//         repeated == null ? '—' : '${repeated['count']}× calls';
//     final repeatedDuration = repeated?['durationStr']?.toString() ?? '';

//     return Scaffold(
//       backgroundColor: AppTheme.paper,
//       body: RefreshIndicator(
//         color: AppTheme.greenNeon,
//         backgroundColor: AppTheme.ink900,
//         onRefresh: () async {
//           await tele.fetchBackendData();
//           await tele.fetchDeviceCallLogs();
//         },
//         child: SingleChildScrollView(
//           physics: const AlwaysScrollableScrollPhysics(),
//           padding: const EdgeInsets.fromLTRB(18, 16, 18, 110),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 'CALL STATS',
//                 style: AppTheme.headline(size: 30, color: AppTheme.ink900),
//               ),
//               const SizedBox(height: 4),
//               Text(
//                 'Your call performance · ${tele.selectedPeriodLabel}',
//                 style: AppTheme.body(size: 12, color: AppTheme.muted),
//               ),
//               const SizedBox(height: 14),
//               Wrap(
//                 spacing: 8,
//                 children: [
//                   _periodButton(tele, 0, 'TODAY'),
//                   _periodButton(tele, 1, 'THIS WEEK'),
//                   _periodButton(tele, 2, 'THIS MONTH'),
//                 ],
//               ),
//               const SizedBox(height: 16),
//               Row(
//                 children: [
//                   Expanded(child: _summaryCard('TOTAL CALLS', '${tele.totalCalls}')),
//                   const SizedBox(width: 12),
//                   Expanded(child: _summaryCard('CONNECTED', '${tele.connectedCalls}')),
//                 ],
//               ),
//               const SizedBox(height: 12),
//               Row(
//                 children: [
//                   Expanded(child: _summaryCard('TALK TIME', tele.talkTimeFormatted)),
//                   const SizedBox(width: 12),
//                   Expanded(child: _summaryCard('AVG. TALK TIME', tele.averageTalkTimeFormatted)),
//                 ],
//               ),
//               const SizedBox(height: 16),
//               NeoCard(
//                 backgroundColor: AppTheme.white,
//                 shadowColor: AppTheme.ink900,
//                 padding: const EdgeInsets.all(16),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Row(
//                       children: [
//                         Container(width: 8, height: 8, color: AppTheme.greenNeon),
//                         const SizedBox(width: 8),
//                         Expanded(
//                           child: Text(
//                             'CALL PERFORMANCE METRICS',
//                             style: AppTheme.label(
//                               size: 10,
//                               color: AppTheme.ink900,
//                               letterSpacing: 0.12,
//                             ),
//                           ),
//                         ),
//                         Text(
//                           tele.selectedPeriodLabel,
//                           style: AppTheme.mono(
//                             size: 9,
//                             color: AppTheme.muted,
//                             weight: FontWeight.w700,
//                           ),
//                         ),
//                       ],
//                     ),
//                     const SizedBox(height: 14),
//                     Wrap(
//                       spacing: 8,
//                       runSpacing: 8,
//                       children: [
//                         _metricBadge('INCOMING', '${tele.incomingCalls}', AppTheme.paper, AppTheme.ink900),
//                         _metricBadge('OUTGOING', '${tele.outgoingCalls}', AppTheme.paper, AppTheme.ink900),
//                         _metricBadge(
//                           'MISSED',
//                           '${tele.missedCalls}',
//                           AppTheme.redMissed.withValues(alpha: 0.12),
//                           AppTheme.redMissed,
//                         ),
//                         _metricBadge('REJECTED', '${tele.rejectedCalls}', AppTheme.limeYellow, AppTheme.ink900),
//                         _metricBadge('NEVER ATTENDED', '${tele.neverAttendedCalls}', AppTheme.paper, AppTheme.ink900),
//                         _metricBadge('UNIQUE CALLS', '${tele.uniqueCalls}', AppTheme.greenNeon, AppTheme.ink900),
//                       ],
//                     ),
//                   ],
//                 ),
//               ),
//               const SizedBox(height: 16),
//               Text(
//                 'TODAY’S CALL HIGHLIGHTS',
//                 style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.12),
//               ),
//               const SizedBox(height: 10),
//               Row(
//                 children: [
//                   Expanded(
//                     child: _highlightCard(
//                       'LONGEST CALL',
//                       longest?.durationFormatted ?? '—',
//                       longestName,
//                     ),
//                   ),
//                   const SizedBox(width: 12),
//                   Expanded(
//                     child: _highlightCard(
//                       'MOST REPEATED',
//                       repeatedCount,
//                       repeatedName,
//                       subtext: repeatedDuration,
//                     ),
//                   ),
//                 ],
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _periodButton(TeleProvider tele, int period, String label) {
//     final selected = tele.selectedTimeFilter == period &&
//         tele.selectedCustomDate == null &&
//         tele.selectedDateRange == null;
//     return GestureDetector(
//       onTap: () => tele.setTimeFilter(period),
//       child: Container(
//         padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//         decoration: BoxDecoration(
//           color: selected ? AppTheme.ink900 : AppTheme.white,
//           borderRadius: BorderRadius.circular(999),
//           border: Border.all(color: AppTheme.ink900, width: 1),
//         ),
//         child: Text(
//           label,
//           style: AppTheme.mono(
//             size: 9,
//             color: selected ? AppTheme.limeYellow : AppTheme.ink900,
//             weight: FontWeight.w700,
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _summaryCard(String label, String value) {
//     return NeoCard(
//       backgroundColor: AppTheme.white,
//       padding: const EdgeInsets.all(14),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text(label, style: AppTheme.label(size: 8.5, color: AppTheme.muted, letterSpacing: 0.1)),
//           const SizedBox(height: 6),
//           Text(
//             value,
//             style: AppTheme.headline(size: 24, color: AppTheme.ink900),
//             maxLines: 1,
//             overflow: TextOverflow.ellipsis,
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _metricBadge(String label, String value, Color background, Color foreground) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
//       decoration: BoxDecoration(
//         color: background,
//         borderRadius: BorderRadius.circular(10),
//         border: Border.all(color: AppTheme.ink900, width: 1.2),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           Text(
//             label,
//             style: AppTheme.label(
//               size: 8,
//               color: foreground == AppTheme.white ? AppTheme.limeYellow : AppTheme.ink900,
//               letterSpacing: 0.08,
//             ),
//           ),
//           const SizedBox(height: 2),
//           Text(value, style: AppTheme.headline(size: 18, color: foreground)),
//         ],
//       ),
//     );
//   }

//   Widget _highlightCard(String label, String value, String description, {String subtext = ''}) {
//     return NeoCard(
//       backgroundColor: AppTheme.white,
//       padding: const EdgeInsets.all(14),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text(label, style: AppTheme.label(size: 8.5, color: AppTheme.muted, letterSpacing: 0.1)),
//           const SizedBox(height: 6),
//           Text(
//             value,
//             style: AppTheme.headline(size: 21, color: label == 'MOST REPEATED' ? AppTheme.greenDark : AppTheme.ink900),
//             maxLines: 1,
//             overflow: TextOverflow.ellipsis,
//           ),
//           if (subtext.isNotEmpty) ...[
//             const SizedBox(height: 3),
//             Text(subtext, style: AppTheme.mono(size: 8.5, color: AppTheme.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
//           ],
//           const SizedBox(height: 3),
//           Text(
//             description,
//             style: AppTheme.body(size: 11, color: AppTheme.muted),
//             maxLines: 1,
//             overflow: TextOverflow.ellipsis,
//           ),
//         ],
//       ),
//     );
//   }
// }
