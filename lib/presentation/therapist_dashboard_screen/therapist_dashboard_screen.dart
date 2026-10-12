import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/payment_booking_store.dart';
import '../../data/therapist_roster_store.dart';
import '../../models/booking.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';

class TherapistDashboardScreen extends StatefulWidget {
  const TherapistDashboardScreen({required this.email, super.key});

  final String email;

  @override
  State<TherapistDashboardScreen> createState() =>
      _TherapistDashboardScreenState();
}

class _TherapistDashboardScreenState extends State<TherapistDashboardScreen> {
  DateTime _selectedDate = DateUtils.dateOnly(DateTime.now());

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.backgroundLight,
    appBar: AppBar(
      title: const Text('Therapist Dashboard'),
      backgroundColor: AppTheme.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      actions: [
        IconButton(
          tooltip: 'Log out',
          onPressed: () => context.go(AppRoutes.initial),
          icon: const Icon(Icons.logout_rounded),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: TherapistRosterStore.instance,
      builder: (context, _) {
        final therapist = TherapistRosterStore.instance.findByEmail(
          widget.email,
        );
        if (therapist == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'This login email is not linked to a therapist profile yet. Ask the admin to add the therapist using this email.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final isOnDuty = TherapistRosterStore.instance.isOnDuty(
          therapist.id,
          _selectedDate,
        );
        return AnimatedBuilder(
          animation: PaymentBookingStore.instance,
          builder: (context, _) {
            final bookings =
                PaymentBookingStore.instance.bookings
                    .where(
                      (booking) =>
                          booking.therapistId == therapist.id &&
                          _sameDay(booking.appointmentDate, _selectedDate),
                    )
                    .toList()
                  ..sort(
                    (first, second) =>
                        _minutesFromTime(first.startTime)
                            .compareTo(_minutesFromTime(second.startTime)),
                  );
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              children: [
                Text(
                  'Hello, ${therapist.name}',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  therapist.specialty,
                  style: const TextStyle(color: AppTheme.onSurfaceVariantLight),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: _chooseDate,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(_formatDate(_selectedDate)),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isOnDuty
                        ? AppTheme.primaryContainer
                        : const Color(0xFFFFF4E5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isOnDuty
                            ? Icons.check_circle_outline_rounded
                            : Icons.event_busy_outlined,
                        color: isOnDuty ? AppTheme.primary : AppTheme.warning,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isOnDuty
                              ? 'You are on duty this day.'
                              : 'You are not assigned to work this day.',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Appointments (${bookings.length})',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                if (bookings.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text('No appointments assigned for this day.'),
                  )
                else
                  for (final booking in bookings)
                    _AppointmentCard(booking: booking),
              ],
            );
          },
        );
      },
    ),
  );

  Future<void> _chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (date != null && mounted) {
      setState(() => _selectedDate = DateUtils.dateOnly(date));
    }
  }

  bool _sameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  int _minutesFromTime(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$').firstMatch(value);
    if (match == null) return 0;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final isPm = match.group(3) == 'PM';
    return ((hour % 12) + (isPm ? 12 : 0)) * 60 + minute;
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: Colors.black12),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  booking.startTime,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              Text(booking.bookingStatus.label),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            booking.serviceName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text('Client: ${booking.clientName}'),
          Text('Duration: ${booking.durationMinutes} minutes'),
          Text('Booking ref: ${booking.referenceNumber}'),
        ],
      ),
    ),
  );
}
