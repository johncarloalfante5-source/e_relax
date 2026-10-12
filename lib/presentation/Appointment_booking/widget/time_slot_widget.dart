import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

class TimeSlotWidget extends StatelessWidget {
  final String? selectedTimeSlot;
  final void Function(String) onTimeSelected;
  final DateTime? selectedDate;

  const TimeSlotWidget({
    super.key,
    required this.selectedTimeSlot,
    required this.onTimeSelected,
    this.selectedDate,
  });

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
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: selectedTimeSlot,
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
      items: _timeSlots
          .map(
            (time) => DropdownMenuItem(
              value: time,
              child: Text(
                time,
                style: GoogleFonts.plusJakartaSans(fontSize: 14),
              ),
            ),
          )
          .toList(),
      onChanged: (time) {
        if (time != null) onTimeSelected(time);
      },
    );
  }
}
