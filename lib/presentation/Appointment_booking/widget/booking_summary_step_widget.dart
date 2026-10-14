import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../data/therapist_roster_store.dart';
import '../../../models/booking.dart';
import '../../../theme/app_theme.dart';
import '../../../widget/custom_icon_widget.dart';

class BookingSummaryStepWidget extends StatelessWidget {
  final Map<String, dynamic> serviceData;
  final DateTime? selectedDate;
  final String? selectedTimeSlot;
  final String? selectedTherapistId;

  const BookingSummaryStepWidget({
    super.key,
    required this.serviceData,
    this.selectedDate,
    this.selectedTimeSlot,
    this.selectedTherapistId,
  });

  String get _formattedDate {
    if (selectedDate == null) return 'Not selected';
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[selectedDate!.month - 1]} ${selectedDate!.day}, ${selectedDate!.year}';
  }

  String get _therapistName => selectedTherapistId == null
      ? 'Not selected'
      : TherapistRosterStore.instance.findById(selectedTherapistId!)?.name ??
            'Not selected';

  double get _serviceTotal => (serviceData['price'] as num).toDouble();
  double get _downPaymentAmount => Booking.calculateDownPayment(_serviceTotal);
  double get _remainingBalance => _serviceTotal - _downPaymentAmount;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Review Your Booking',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.onSurfaceLight,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Please review the details before proceeding to payment.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: AppTheme.onSurfaceVariantLight,
            ),
          ),
          const SizedBox(height: 20),

          // Summary detail rows — anatomy locked from reference image
          // Each row: circle icon bg + label/value column + divider
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildSummaryRow(
                  icon: 'person_outline',
                  label: 'Therapist',
                  value: _therapistName,
                ),
                _buildDivider(),
                _buildSummaryRow(
                  icon: 'spa',
                  label: 'Service',
                  value: serviceData['name'] as String,
                ),
                _buildDivider(),
                _buildSummaryRow(
                  icon: 'calendar_today',
                  label: 'Date & Time',
                  value:
                      '$_formattedDate\n${selectedTimeSlot ?? 'Not selected'}',
                ),
                _buildDivider(),
                _buildSummaryRow(
                  icon: 'location_on_outlined',
                  label: 'Location',
                  value: 'E-Relax Massage Clinic\nMain Branch',
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Payment Details section — anatomy locked from reference image
          Text(
            'Payment Details',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildPaymentLine(
                  serviceData['name'] as String,
                  '₱${_serviceTotal.toStringAsFixed(0)}',
                ),
                const SizedBox(height: 10),
                _buildPaymentLine(
                  'Duration',
                  '${serviceData['durationMinutes']} min',
                ),
                const SizedBox(height: 10),
                const SizedBox(height: 12),
                // Dashed divider
                Row(
                  children: List.generate(
                    30,
                    (i) => Expanded(
                      child: Container(
                        height: 1,
                        color: i.isEven
                            ? AppTheme.primary.withAlpha(77)
                            : Colors.transparent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Service total',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.onSurfaceLight,
                      ),
                    ),
                    Text(
                      '₱${_serviceTotal.toStringAsFixed(0)}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.secondary,
                        fontFeatures: [const FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Down payment preview notice
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.warning.withAlpha(102)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomIconWidget(
                  iconName: 'warning_amber_rounded',
                  color: AppTheme.warning,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Down Payment Required',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.warning,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'A down payment of ₱${_downPaymentAmount.toStringAsFixed(0)} (30%) is required to confirm your reservation. Remaining balance of ₱${_remainingBalance.toStringAsFixed(0)} is due after service.',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: const Color(0xFF795548),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // BookingSummaryRowWidget anatomy locked from reference image:
  // circle icon bg + label/value column + divider
  Widget _buildSummaryRow({
    required String icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: CustomIconWidget(
                iconName: icon,
                color: AppTheme.primary,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.onSurfaceVariantLight,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.onSurfaceLight,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: AppTheme.surfaceVariantLight,
      indent: 16,
      endIndent: 16,
    );
  }

  Widget _buildPaymentLine(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: AppTheme.onSurfaceVariantLight,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.onSurfaceLight,
            fontFeatures: [const FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
