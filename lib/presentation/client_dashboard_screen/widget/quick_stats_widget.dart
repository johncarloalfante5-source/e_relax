import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../data/payment_booking_store.dart';
import '../../../models/booking.dart';
import '../../../theme/app_theme.dart';
import '../../../widget/custom_icon_widget.dart';

class QuickStatsWidget extends StatelessWidget {
  const QuickStatsWidget({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: PaymentBookingStore.instance,
    builder: (context, _) {
      final bookings = PaymentBookingStore.instance.bookingsForClient(
        ClientSession.instance.clientId,
      );
      final today = DateUtils.dateOnly(DateTime.now());
      final activeBookings = bookings
          .where((booking) => booking.bookingStatus != BookingStatus.cancelled)
          .toList();
      final upcoming = activeBookings.where((booking) {
        final status = booking.bookingStatus;
        return !booking.appointmentDate.isBefore(today) &&
            status != BookingStatus.completed;
      }).length;
      final completed = bookings
          .where((booking) => booking.bookingStatus == BookingStatus.completed)
          .length;

      final stats = [
        _ClientStat(
          label: 'Sessions',
          value: activeBookings.length,
          icon: 'spa',
          color: AppTheme.primary,
        ),
        _ClientStat(
          label: 'Upcoming',
          value: upcoming,
          icon: 'calendar_today',
          color: AppTheme.secondary,
        ),
        _ClientStat(
          label: 'Completed',
          value: completed,
          icon: 'check_circle_outline',
          color: const Color(0xFF01579B),
        ),
      ];

      return Row(
        children: [
          for (var index = 0; index < stats.length; index++)
            Expanded(
              child: Container(
                margin: EdgeInsets.only(
                  right: index == stats.length - 1 ? 0 : 8,
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(13),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: stats[index].color.withAlpha(31),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: CustomIconWidget(
                          iconName: stats[index].icon,
                          color: stats[index].color,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      stats[index].value.toString(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.onSurfaceLight,
                        fontFeatures: [const FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stats[index].label,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        color: AppTheme.onSurfaceVariantLight,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _ClientStat {
  const _ClientStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final String icon;
  final Color color;
}
