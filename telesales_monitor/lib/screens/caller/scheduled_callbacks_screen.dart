import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neo_card.dart';
import '../../widgets/neo_button.dart';
import '../../providers/tele_provider.dart';

class ScheduledCallbacksScreen extends StatelessWidget {
  const ScheduledCallbacksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, color: AppTheme.greenNeon),
              const SizedBox(width: 8),
              Text(
                'FOLLOW-UP CALLS · ${tele.callbacks.length}',
                style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: tele.callbacks.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final cb = tele.callbacks[index];
              final isSnoozed = cb.isSnoozed;

              return NeoCard(
                backgroundColor: isSnoozed ? AppTheme.paper : AppTheme.white,
                shadowColor: AppTheme.ink900,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(cb.name, style: AppTheme.bodyBold(size: 13)),
                        Text(
                          '${cb.scheduledTime.hour}:${cb.scheduledTime.minute.toString().padLeft(2, '0')} PM',
                          style: AppTheme.mono(size: 11, color: AppTheme.ink900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      cb.note,
                      style: AppTheme.body(size: 11, color: AppTheme.ink700),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: NeoButton.pill(
                            backgroundColor: AppTheme.limeYellow,
                            shadowColor: AppTheme.ink900,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Center(
                              child: Text(
                                '☎ CALL NOW',
                                style: AppTheme.label(size: 10, color: AppTheme.ink900, letterSpacing: 0.1),
                              ),
                            ),
                            onTap: () => tele.launchCall(cb.phone),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: NeoButton.pill(
                            backgroundColor: isSnoozed ? AppTheme.ink900 : AppTheme.white,
                            shadowColor: AppTheme.ink900,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Center(
                              child: Text(
                                isSnoozed ? 'SNOOZED' : 'SNOOZE +30M',
                                style: AppTheme.label(
                                  size: 10,
                                  color: isSnoozed ? AppTheme.white : AppTheme.ink900,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ),
                            onTap: () => tele.snoozeCallback(cb.id),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
