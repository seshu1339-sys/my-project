import 'package:flutter/material.dart';

import '../domain/ist_time.dart';

/// Asks for a date and then a time, both India time (IST), for an ad's or a box's start / end. Returns that moment, or null when
/// either step was cancelled. [endOfDay] starts the time picker at 23:59 (a new end date usually means "until the end of that day").
Future<DateTime?> pickIstDateTime(BuildContext context, {required DateTime initial, String helpText = '', bool endOfDay = false}) async {
  final w = istWallClock(initial);
  final date = await showDatePicker(
    context: context,
    initialDate: DateTime(w.year, w.month, w.day),
    firstDate: DateTime(2024),
    lastDate: DateTime(2100),
    helpText: helpText.isEmpty ? null : helpText,
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: endOfDay ? const TimeOfDay(hour: 23, minute: 59) : TimeOfDay(hour: w.hour, minute: w.minute),
    helpText: helpText.isEmpty ? 'Time (India)' : '$helpText: time',
  );
  if (time == null) return null;
  return istMoment(date.year, date.month, date.day, time.hour, time.minute);
}
