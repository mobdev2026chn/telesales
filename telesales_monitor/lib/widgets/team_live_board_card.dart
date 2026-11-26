import 'package:flutter/material.dart';

import '../services/api_parsers.dart';
import '../theme/app_theme.dart';
import 'neo_card.dart';

/// Read-only live team board for the manager home screen: how many members are on a call,
/// available, on a break, offline, and (when the server says) have call recording off.
/// Tapping a count shows the names. Data comes from the dashboard stats already loaded.
class TeamLiveBoardCard extends StatefulWidget {
  final TeamLiveBoard board;

  const TeamLiveBoardCard({super.key, required this.board});

  @override
  State<TeamLiveBoardCard> createState() => _TeamLiveBoardCardState();
}

class _TeamLiveBoardCardState extends State<TeamLiveBoardCard> {
  static const String _recOffKey = 'recOff';
  String? _open; // TeamLiveState name, or _recOffKey

  void _toggle(String key) => setState(() => _open = _open == key ? null : key);

  static String _labelFor(TeamLiveState s) => switch (s) {
        TeamLiveState.onCall => 'ON CALL',
        TeamLiveState.available => 'AVAILABLE',
        TeamLiveState.onBreak => 'ON BREAK',
        TeamLiveState.offline => 'OFFLINE',
      };

  static Color _colorFor(TeamLiveState s) => switch (s) {
        TeamLiveState.onCall => AppTheme.orangePill,
        TeamLiveState.available => AppTheme.greenNeon,
        TeamLiveState.onBreak => AppTheme.limeYellow,
        TeamLiveState.offline => AppTheme.muted,
      };

  @override
  Widget build(BuildContext context) {
    final board = widget.board;
    final recOff = board.recordingOffNames;

    List<String> openNames = const [];
    if (_open == _recOffKey) {
      openNames = [...?recOff]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    } else if (_open != null) {
      final state = TeamLiveState.values.firstWhere((s) => s.name == _open, orElse: () => TeamLiveState.offline);
      openNames = board
          .inState(state)
          .map((m) => m.breakType.isNotEmpty ? '${m.name} · ${m.breakType}' : m.name)
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }

    return NeoCard(
      backgroundColor: AppTheme.white,
      shadowColor: AppTheme.ink900,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LIVE TEAM BOARD',
                style: AppTheme.label(size: 9, color: AppTheme.ink900, letterSpacing: 0.18),
              ),
              Text(
                '${board.members.length} MEMBERS',
                style: AppTheme.mono(size: 9, color: AppTheme.muted, weight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final s in TeamLiveState.values) ...[
                if (s != TeamLiveState.values.first) const SizedBox(width: 6),
                Expanded(
                  child: _CountTile(
                    label: _labelFor(s),
                    count: board.inState(s).length,
                    dotColor: _colorFor(s),
                    selected: _open == s.name,
                    onTap: () => _toggle(s.name),
                  ),
                ),
              ],
            ],
          ),
          if (recOff != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _toggle(_recOffKey),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _open == _recOffKey ? AppTheme.ink900 : AppTheme.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: recOff.isNotEmpty ? AppTheme.redMissed : AppTheme.ink900,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.mic_off_rounded,
                      size: 14,
                      color: recOff.isNotEmpty
                          ? AppTheme.redMissed
                          : (_open == _recOffKey ? AppTheme.limeYellow : AppTheme.muted),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'RECORDING OFF · ${recOff.length}',
                        style: AppTheme.label(
                          size: 9,
                          color: _open == _recOffKey ? AppTheme.limeYellow : AppTheme.ink900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_open != null) ...[
            const SizedBox(height: 10),
            if (openNames.isEmpty)
              Text('Nobody right now.', style: AppTheme.body(size: 11, color: AppTheme.muted))
            else
              for (final n in openNames)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _open == _recOffKey
                              ? AppTheme.redMissed
                              : _colorFor(TeamLiveState.values.firstWhere((s) => s.name == _open)),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.ink900, width: 0.6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          n,
                          style: AppTheme.bodyBold(size: 12, color: AppTheme.ink900),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
          const SizedBox(height: 8),
          Text(
            'On call = a call in the last 15 min. Tap a count to see who.',
            style: AppTheme.body(size: 10, color: AppTheme.muted),
          ),
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  final String label;
  final int count;
  final Color dotColor;
  final bool selected;
  final VoidCallback onTap;

  const _CountTile({
    required this.label,
    required this.count,
    required this.dotColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.ink900 : AppTheme.paper,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.ink900, width: 1.2),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: AppTheme.headline(size: 22, color: selected ? AppTheme.white : AppTheme.ink900),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.ink900, width: 0.6),
                  ),
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: AppTheme.label(size: 7.5, color: selected ? AppTheme.limeYellow : AppTheme.ink900),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Team daily target vs. calls today (server-counted) for the manager home screen.
class TeamTargetCard extends StatelessWidget {
  final int target;
  final int calls;

  const TeamTargetCard({super.key, required this.target, required this.calls});

  @override
  Widget build(BuildContext context) {
    final progress = target > 0 ? (calls / target).clamp(0.0, 1.0) : 0.0;
    final percent = target > 0 ? (calls * 100 / target).round() : 0;
    return NeoCard(
      backgroundColor: AppTheme.white,
      shadowColor: AppTheme.ink900,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TEAM TARGET · TODAY',
                style: AppTheme.label(size: 9, color: AppTheme.ink900, letterSpacing: 0.18),
              ),
              Text(
                '$percent%',
                style: AppTheme.mono(size: 11, color: AppTheme.greenDark, weight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$calls', style: AppTheme.headline(size: 28, color: AppTheme.ink900)),
              const SizedBox(width: 6),
              Text('/ $target calls', style: AppTheme.body(size: 12, color: AppTheme.muted)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: AppTheme.paper,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppTheme.ink900, width: 0.8),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress,
                child: Container(color: AppTheme.greenNeon),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            calls >= target ? 'Daily target reached.' : '${target - calls} calls to go · sum of each member\'s daily target',
            style: AppTheme.body(size: 11, color: AppTheme.muted),
          ),
        ],
      ),
    );
  }
}
