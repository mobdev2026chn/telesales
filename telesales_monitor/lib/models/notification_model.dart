import 'package:intl/intl.dart';

class NotificationItem {
  final String id;
  final String recipientPhone;
  final String recipientName;
  final String senderName;
  final String senderRole;
  final String recordingId;
  final String contactName;
  final String title;
  final String message;
  final String comment;
  final int rating;
  bool isRead;
  final DateTime createdAt;

  NotificationItem({
    required this.id,
    required this.recipientPhone,
    required this.recipientName,
    required this.senderName,
    required this.senderRole,
    required this.recordingId,
    required this.contactName,
    required this.title,
    required this.message,
    required this.comment,
    required this.rating,
    this.isRead = false,
    required this.createdAt,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      recipientPhone: json['recipientPhone']?.toString() ?? '',
      recipientName: json['recipientName']?.toString() ?? '',
      senderName: json['senderName']?.toString() ?? 'Admin',
      senderRole: json['senderRole']?.toString() ?? 'admin',
      recordingId: json['recordingId']?.toString() ?? '',
      contactName: json['contactName']?.toString() ?? 'Client',
      title: json['title']?.toString() ?? 'New Feedback',
      message: json['message']?.toString() ?? '',
      comment: json['comment']?.toString() ?? '',
      rating: (json['rating'] is int)
          ? json['rating'] as int
          : (json['rating'] is double)
              ? (json['rating'] as double).toInt()
              : 0,
      isRead: json['isRead'] == true,
      createdAt: json['createdAt'] != null
          ? (DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('d MMM, h:mm a').format(createdAt);
  }
}
