import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class RecordingModel {
  final String id;
  final String agentName;
  final String clientName;
  final String clientPhone;
  final DateTime date;
  final Duration duration;
  final String note;
  final String audioUrl;
  final String fileName;
  String filePath;
  final String? audioData;
  bool isPlaying;
  double progress;
  Duration playbackPosition = Duration.zero;
  Duration? playbackDuration; // real length reported by the player
  int rating;
  String comment;
  String commentedBy;
  String commentedByRole;
  DateTime? commentedAt;
  /// Pinned by an admin / manager from the portal; pinned recordings are listed first.
  bool pinned;

  RecordingModel({
    required this.id,
    required this.agentName,
    required this.clientName,
    required this.clientPhone,
    required this.date,
    required this.duration,
    required this.note,
    this.audioUrl = '',
    this.fileName = '',
    this.filePath = '',
    this.audioData,
    this.isPlaying = false,
    this.progress = 0.0,
    this.rating = 0,
    this.comment = '',
    this.commentedBy = '',
    this.commentedByRole = '',
    this.commentedAt,
    this.pinned = false,
  });

  factory RecordingModel.fromJson(Map<String, dynamic> json) {
    final durationSec = ((json['durationSeconds'] ?? json['duration']) as num?)?.toInt() ?? 0;

    DateTime parsedDate = DateTime.now();
    if (json['createdAt'] != null) {
      parsedDate = DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now();
    }

    return RecordingModel(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? UniqueKey().toString(),
      agentName: json['callerName']?.toString() ?? json['agentName']?.toString() ?? 'Caller',
      clientName: json['contactName']?.toString() ?? json['clientName']?.toString() ?? 'Client',
      clientPhone: json['phoneNumber']?.toString() ?? json['clientPhone']?.toString() ?? '',
      date: parsedDate,
      duration: Duration(seconds: durationSec),
      note: json['transcript']?.toString() ?? json['note']?.toString() ?? '',
      audioUrl: json['audioUrl']?.toString() ?? '',
      audioData: json['audioData']?.toString() ?? '',
      rating: (json['rating'] is num) ? (json['rating'] as num).toInt() : 0,
      comment: json['comment']?.toString() ?? '',
      commentedBy: json['commentedBy']?.toString() ?? '',
      commentedByRole: json['commentedByRole']?.toString() ?? '',
      commentedAt: json['commentedAt'] != null ? DateTime.tryParse(json['commentedAt'].toString()) : null,
      pinned: json['pinned'] == true,
    );
  }

  String get callerName => agentName;
  String get contactName => clientName;
  String get phoneNumber => clientPhone;
  String get quote => note;
  String get dateStr => DateFormat('d MMM').format(date);
  String get timeStr => DateFormat('h:mm a').format(date);

  String get durationFormatted {
    final m = duration.inMinutes;
    final s = duration.inSeconds % 60;
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}
