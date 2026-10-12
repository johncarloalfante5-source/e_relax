import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

class DaySelectorWidget extends StatelessWidget {
  final DateTime? selectedDate;
  final void Function(DateTime) onDateSelected;

  const DaySelectorWidget({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
  });

  static const List<String> _dayAbbreviations = [
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT',
    'SUN',
  ];

  List<DateTime> _getDaysForCurrentWeek() {
    final now = DateTime.now();
    // Start from today and show 14 days
    return List.generate(14, (i) => now.add(Duration(days: i)));
  }

  @override
  Widget build(BuildContext context) {
    final days = _getDaysForCurrentWeek();

    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final day = days[i];
          final isSelected =
              selectedDate != null &&
              day.year == selectedDate!.year &&
              day.month == selectedDate!.month &&
              day.day == selectedDate!.day;
          final dayAbbr = _dayAbbreviations[day.weekday - 1];
          final isToday =
              day.day == DateTime.now().day &&
              day.month == DateTime.now().month;

          return GestureDetector(
            onTap: () => onDateSelected(day),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              width: 58,
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primary : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected
                      ? AppTheme.primary
                      : isToday
                      ? AppTheme.primary.withAlpha(102)
                      : AppTheme.surfaceVariantLight,
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppTheme.primary.withAlpha(77),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withAlpha(10),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    dayAbbr,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white.withAlpha(204)
                          : AppTheme.onSurfaceVariantLight,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${day.day}'.padLeft(2, '0'),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isSelected
                          ? Colors.white
                          : AppTheme.onSurfaceLight,
                      fontFeatures: [const FontFeature.tabularFigures()],
                    ),
                  ),
                  if (isToday && !isSelected) ...[
                    const SizedBox(height: 3),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.secondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
