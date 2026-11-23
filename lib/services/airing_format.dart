import 'package:intl/intl.dart';

/// Live countdown text for an airing episode (pure — unit-tested):
/// "in 2d 4h", "in 3h 12m", "in 45m", "in 1m", "Airing now".
String formatAiringCountdown(DateTime airingAt, {DateTime? now}) {
  final Duration left = airingAt.difference(now ?? DateTime.now());
  if (left <= Duration.zero) return 'Airing now';
  if (left.inDays > 0) {
    return 'in ${left.inDays}d ${left.inHours % 24}h';
  }
  if (left.inHours > 0) {
    return 'in ${left.inHours}h ${left.inMinutes % 60}m';
  }
  if (left.inMinutes > 0) return 'in ${left.inMinutes}m';
  return 'in ${left.inSeconds}s';
}

/// Air date for the Detail empty state / next-episode line (0.2.13):
/// "Nov 29 at 22:05", in the phone's local time. Pure.
String formatAiringDate(DateTime airingAt) {
  final DateTime local = airingAt.toLocal();
  return "${DateFormat('MMM d').format(local)} at "
      "${DateFormat('HH:mm').format(local)}";
}
