import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

bool isAppointmentTimePast(DateTime date, String time, {DateTime? now}) {
  final currentTime = now ?? DateTime.now();
  if (!DateUtils.isSameDay(date, currentTime)) return false;

  final parts = time.trim().split(RegExp(r'\s+'));
  if (parts.length != 2) return false;
  final clockParts = parts.first.split(':');
  if (clockParts.length != 2) return false;
  final hour12 = int.tryParse(clockParts[0]);
  final minute = int.tryParse(clockParts[1]);
  if (hour12 == null || minute == null || hour12 < 1 || hour12 > 12) {
    return false;
  }

  final period = parts[1].toUpperCase();
  if (period != 'AM' && period != 'PM') return false;
  var hour = hour12 % 12;
  if (period == 'PM') hour += 12;

  final slotTime = DateTime(date.year, date.month, date.day, hour, minute);
  return !slotTime.isAfter(currentTime);
}

class TimeSlotWidget extends StatefulWidget {
  final String? selectedTimeSlot;
  final void Function(String) onTimeSelected;
  final VoidCallback? onSelectedTimeExpired;
  final DateTime? selectedDate;

  const TimeSlotWidget({
    super.key,
    required this.selectedTimeSlot,
    required this.onTimeSelected,
    this.onSelectedTimeExpired,
    this.selectedDate,
  });

  @override
  State<TimeSlotWidget> createState() => _TimeSlotWidgetState();
}

class _TimeSlotWidgetState extends State<TimeSlotWidget> {
  late DateTime _now;
  Timer? _clock;

  static List<String> get _timeSlots => [
    for (var minutes = 11 * 60; minutes <= 20 * 60; minutes += 5)
      _formatTime(minutes),
  ];

  static String _formatTime(int minutes) {
    final hour24 = minutes ~/ 60;
    final minute = minutes % 60;
    final period = hour24 < 12 ? 'AM' : 'PM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '$hour12:${minute.toString().padLeft(2, '0')} $period';
  }

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      _refreshCurrentTime();
    });
  }

  @override
  void didUpdateWidget(covariant TimeSlotWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!DateUtils.isSameDay(oldWidget.selectedDate, widget.selectedDate)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshCurrentTime();
      });
    }
  }

  void _refreshCurrentTime() {
    if (!mounted) return;
    setState(() => _now = DateTime.now());
    final date = widget.selectedDate;
    final selectedTime = widget.selectedTimeSlot;
    if (date != null &&
        selectedTime != null &&
        isAppointmentTimePast(date, selectedTime, now: _now)) {
      widget.onSelectedTimeExpired?.call();
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: widget.selectedTimeSlot,
      isExpanded: true,
      menuMaxHeight: 360,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.access_time_rounded),
        hintText: 'Choose a time',
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.primary.withAlpha(77)),
        ),
      ),
      items: _timeSlots.map((time) {
        final isPast = widget.selectedDate != null &&
            isAppointmentTimePast(widget.selectedDate!, time, now: _now);
        return DropdownMenuItem<String>(
          value: time,
          enabled: !isPast,
          child: Text(
            time,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: isPast ? Colors.grey.shade500 : null,
            ),
          ),
        );
      }).toList(),
      onChanged: (time) {
        if (time != null) widget.onTimeSelected(time);
      },
    );
  }
}
