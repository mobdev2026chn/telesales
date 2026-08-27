import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/tele_provider.dart';
import '../widgets/neo_card.dart';

class NotificationsSheet extends StatelessWidget {
  const NotificationsSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const NotificationsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tele = Provider.of<TeleProvider>(context);
    final notifs = tele.notifications;
    final unreadCount = tele.unreadNotificationCount;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppTheme.ink900, width: 2),
        boxShadow: AppTheme.neoShadow(color: AppTheme.ink900),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.ink900,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('🔔 ', style: TextStyle(fontSize: 18)),
                  Text(
                    'NOTIFICATIONS',
                    style: AppTheme.headline(size: 16, color: AppTheme.ink900),
                  ),
                  if (unreadCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.orangePill,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$unreadCount NEW',
                        style: AppTheme.label(size: 8.5, color: AppTheme.white),
                      ),
                    ),
                  ],
                ],
              ),
              if (notifs.isNotEmpty && unreadCount > 0)
                GestureDetector(
                  onTap: () => tele.markAllNotificationsRead(),
                  child: Text(
                    'Mark all read',
                    style: AppTheme.label(size: 10, color: AppTheme.greenDark),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Notification List
          if (notifs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.notifications_off_outlined, size: 40, color: AppTheme.muted),
                    const SizedBox(height: 10),
                    Text('NO NOTIFICATIONS', style: AppTheme.headline(size: 14)),
                    const SizedBox(height: 4),
                    Text(
                      'When Admin or Manager reviews your calls, comments and ratings will show up here.',
                      textAlign: TextAlign.center,
                      style: AppTheme.body(size: 11, color: AppTheme.muted),
                    ),
                  ],
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: notifs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (ctx, idx) {
                  final notif = notifs[idx];

                  return GestureDetector(
                    onTap: () {
                      if (!notif.isRead) {
                        tele.markNotificationRead(notif.id);
                      }
                    },
                    child: NeoCard(
                      backgroundColor: notif.isRead ? AppTheme.white : AppTheme.white,
                      shadowColor: AppTheme.ink900,
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  if (!notif.isRead)
                                    Container(
                                      width: 8,
                                      height: 8,
                                      margin: const EdgeInsets.only(right: 6),
                                      decoration: const BoxDecoration(
                                        color: AppTheme.orangePill,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  Text(
                                    notif.title,
                                    style: AppTheme.bodyBold(size: 12, color: AppTheme.ink900),
                                  ),
                                ],
                              ),
                              Text(
                                notif.timeAgo,
                                style: AppTheme.mono(size: 9, color: AppTheme.muted),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (notif.rating > 0) ...[
                            Row(
                              children: [
                                Row(
                                  children: List.generate(5, (sIdx) {
                                    final filled = sIdx < notif.rating;
                                    return Icon(
                                      filled ? Icons.star_rounded : Icons.star_outline_rounded,
                                      size: 14,
                                      color: filled ? AppTheme.orangePill : AppTheme.muted,
                                    );
                                  }),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${notif.rating}/5 Stars',
                                  style: AppTheme.label(size: 8.5, color: AppTheme.greenDark),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],
                          Text(
                            notif.message,
                            style: AppTheme.body(size: 11.5, color: AppTheme.ink900),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
