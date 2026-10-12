import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'widget/upcoming_booking_widget.dart';

class ClientBookingsScreen extends StatelessWidget {
  const ClientBookingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.backgroundLight,
    appBar: AppBar(
      title: const Text('My Bookings'),
      backgroundColor: AppTheme.primary,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 108),
        children: [
          Text(
            'Appointments and payments',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Track your upcoming visits, payment reviews, and past appointments.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.onSurfaceVariantLight,
            ),
          ),
          const SizedBox(height: 18),
          const UpcomingBookingWidget(showFilters: true),
        ],
      ),
    ),
  );
}
