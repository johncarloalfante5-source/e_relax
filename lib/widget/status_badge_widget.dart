import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

enum BookingStatus {
  pending,
  awaitingPayment,
  paymentVerification,
  confirmed,
  checkedIn,
  inProgress,
  completed,
  cancelled,
  rejected,
  noShow,
}

enum PaymentStatus {
  unpaid,
  downPayment,
  partiallyPaid,
  fullyPaid,
  pendingVerification,
  verified,
  rejected,
}

class StatusBadgeWidget extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final double fontSize;

  const StatusBadgeWidget({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    this.fontSize = 11,
  });

  factory StatusBadgeWidget.fromBookingStatus(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return StatusBadgeWidget(
          label: 'Pending',
          backgroundColor: const Color(0xFFFFF3E0),
          textColor: AppTheme.warning,
        );
      case BookingStatus.awaitingPayment:
        return StatusBadgeWidget(
          label: 'Awaiting Payment',
          backgroundColor: const Color(0xFFFFF3E0),
          textColor: AppTheme.warning,
        );
      case BookingStatus.paymentVerification:
        return StatusBadgeWidget(
          label: 'Verifying Payment',
          backgroundColor: const Color(0xFFE3F2FD),
          textColor: AppTheme.info,
        );
      case BookingStatus.confirmed:
        return StatusBadgeWidget(
          label: 'Confirmed',
          backgroundColor: const Color(0xFFE8F5E9),
          textColor: AppTheme.success,
        );
      case BookingStatus.checkedIn:
        return StatusBadgeWidget(
          label: 'Checked In',
          backgroundColor: AppTheme.primaryContainer,
          textColor: AppTheme.primary,
        );
      case BookingStatus.inProgress:
        return StatusBadgeWidget(
          label: 'In Progress',
          backgroundColor: const Color(0xFFE8F5E9),
          textColor: AppTheme.primary,
        );
      case BookingStatus.completed:
        return StatusBadgeWidget(
          label: 'Completed',
          backgroundColor: AppTheme.primaryContainer,
          textColor: AppTheme.primary,
        );
      case BookingStatus.cancelled:
        return StatusBadgeWidget(
          label: 'Cancelled',
          backgroundColor: const Color(0xFFFFEBEE),
          textColor: AppTheme.error,
        );
      case BookingStatus.rejected:
        return StatusBadgeWidget(
          label: 'Rejected',
          backgroundColor: const Color(0xFFFFEBEE),
          textColor: AppTheme.error,
        );
      case BookingStatus.noShow:
        return StatusBadgeWidget(
          label: 'No Show',
          backgroundColor: const Color(0xFFF5F5F5),
          textColor: const Color(0xFF757575),
        );
    }
  }

  factory StatusBadgeWidget.fromPaymentStatus(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.unpaid:
        return StatusBadgeWidget(
          label: 'Unpaid',
          backgroundColor: const Color(0xFFFFEBEE),
          textColor: AppTheme.error,
        );
      case PaymentStatus.downPayment:
        return StatusBadgeWidget(
          label: 'Down Payment',
          backgroundColor: const Color(0xFFFFF3E0),
          textColor: AppTheme.warning,
        );
      case PaymentStatus.partiallyPaid:
        return StatusBadgeWidget(
          label: 'Partially Paid',
          backgroundColor: const Color(0xFFFFF3E0),
          textColor: AppTheme.warning,
        );
      case PaymentStatus.fullyPaid:
        return StatusBadgeWidget(
          label: 'Fully Paid',
          backgroundColor: const Color(0xFFE8F5E9),
          textColor: AppTheme.success,
        );
      case PaymentStatus.pendingVerification:
        return StatusBadgeWidget(
          label: 'Pending Verification',
          backgroundColor: const Color(0xFFE3F2FD),
          textColor: AppTheme.info,
        );
      case PaymentStatus.verified:
        return StatusBadgeWidget(
          label: 'Verified',
          backgroundColor: const Color(0xFFE8F5E9),
          textColor: AppTheme.success,
        );
      case PaymentStatus.rejected:
        return StatusBadgeWidget(
          label: 'Rejected',
          backgroundColor: const Color(0xFFFFEBEE),
          textColor: AppTheme.error,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: textColor,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
