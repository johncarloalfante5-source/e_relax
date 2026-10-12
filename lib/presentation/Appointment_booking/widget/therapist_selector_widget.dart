import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../data/payment_booking_store.dart';
import '../../../data/therapist_roster_store.dart';
import '../../../theme/app_theme.dart';
import '../../../widget/custom_image_widget.dart';

class TherapistSelectorWidget extends StatelessWidget {
  final String? selectedTherapistId;
  final void Function(String) onTherapistSelected;
  final DateTime? selectedDate;
  final String? selectedTimeSlot;
  final int durationMinutes;

  const TherapistSelectorWidget({
    super.key,
    required this.selectedTherapistId,
    required this.onTherapistSelected,
    this.selectedDate,
    this.selectedTimeSlot,
    this.durationMinutes = 60,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      TherapistRosterStore.instance,
      PaymentBookingStore.instance,
    ]),
    builder: (context, _) {
      final date = selectedDate;
      final time = selectedTimeSlot;
      if (date == null || time == null) {
        return _availabilityMessage(
          'Choose a date and time to see therapists assigned and available for that appointment.',
        );
      }

      final assigned = TherapistRosterStore.instance.onDutyForDate(date);
      final therapists = TherapistRosterStore.instance.availableForBooking(
        date: date,
        startTime: time,
        durationMinutes: durationMinutes,
      );
      if (therapists.isEmpty) {
        final message = assigned.isEmpty
            ? 'No therapists are assigned to work on this date. Choose another date or contact the clinic.'
            : 'All on-duty therapists are already booked at this time. Choose another time.';
        return _availabilityMessage(message);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppTheme.primaryContainer.withAlpha(128),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.primary.withAlpha(51)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: AppTheme.primary,
                  size: 15,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'On-duty therapists available at $time.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: AppTheme.primary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: therapists.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final therapist = therapists[index];
                final isSelected = selectedTherapistId == therapist.id;
                return GestureDetector(
                  onTap: () => onTherapistSelected(therapist.id),
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.secondary
                                : AppTheme.primary.withAlpha(51),
                            width: isSelected ? 3 : 2,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppTheme.secondary.withAlpha(102),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : [],
                        ),
                        child: ClipOval(
                          child: CustomImageWidget(
                            imageUrl: therapist.imageUrl,
                            width: 68,
                            height: 68,
                            fit: BoxFit.cover,
                            semanticLabel: therapist.semanticLabel,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        therapist.name.split(' ').first,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected
                              ? AppTheme.primary
                              : AppTheme.onSurfaceLight,
                        ),
                      ),
                      Text(
                        therapist.specialty,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          color: AppTheme.onSurfaceVariantLight,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    },
  );

  Widget _availabilityMessage(String message) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.primary.withAlpha(40)),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline_rounded, color: AppTheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ],
    ),
  );
}
