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
  String filePath;
  final String? audioData;
  bool isPlaying;
  double progress;

  RecordingModel({
    required this.id,
    required this.agentName,
    required this.clientName,
    required this.clientPhone,
    required this.date,
    required this.duration,
    required this.note,
    this.audioUrl = '',
    this.filePath = '',
    this.audioData,
    this.isPlaying = false,
    this.progress = 0.0,
  });

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
