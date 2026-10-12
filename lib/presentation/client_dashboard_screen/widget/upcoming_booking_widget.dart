import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../data/payment_booking_store.dart';
import '../../../models/booking.dart';
import '../../../services/booking_receipt_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widget/status_badge_widget.dart' as badges;

class UpcomingBookingWidget extends StatefulWidget {
  const UpcomingBookingWidget({super.key, this.showFilters = false});

  final bool showFilters;

  @override
  State<UpcomingBookingWidget> createState() => _UpcomingBookingWidgetState();
}

enum _BookingFilter { upcoming, past }

class _UpcomingBookingWidgetState extends State<UpcomingBookingWidget> {
  _BookingFilter _filter = _BookingFilter.upcoming;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: PaymentBookingStore.instance,
    builder: (context, _) {
      final bookings = PaymentBookingStore.instance.bookingsForClient(
        localClientSessionId,
      );
      final notices = PaymentBookingStore.instance.noticesForClient(
        localClientSessionId,
      );
      final today = DateUtils.dateOnly(DateTime.now());
      final filteredBookings = bookings.where((booking) {
        final isPast =
            booking.bookingStatus == BookingStatus.completed ||
            booking.bookingStatus == BookingStatus.cancelled ||
            DateUtils.dateOnly(booking.appointmentDate).isBefore(today);
        return _filter == _BookingFilter.past ? isPast : !isPast;
      }).toList()..sort((first, second) {
        final order = first.appointmentDate.compareTo(second.appointmentDate);
        return _filter == _BookingFilter.past ? -order : order;
      });
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.showFilters)
            Text(
              'My Appointments and Payments',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          for (final notice in notices.take(3))
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: notice.type == ClientNoticeType.paymentRejected
                    ? const Color(0xFFFFEBEE)
                    : AppTheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                notice.message,
                style: TextStyle(
                  color: notice.type == ClientNoticeType.paymentRejected
                      ? AppTheme.error
                      : AppTheme.primary,
                  fontSize: 12,
                ),
              ),
            ),
          if (widget.showFilters) ...[
            const SizedBox(height: 8),
            SegmentedButton<_BookingFilter>(
              segments: const [
                ButtonSegment(
                  value: _BookingFilter.upcoming,
                  label: Text('Upcoming'),
                  icon: Icon(Icons.event_available_outlined),
                ),
                ButtonSegment(
                  value: _BookingFilter.past,
                  label: Text('Past'),
                  icon: Icon(Icons.history_rounded),
                ),
              ],
              selected: {_filter},
              onSelectionChanged: (selected) =>
                  setState(() => _filter = selected.first),
            ),
          ],
          const SizedBox(height: 12),
          if (filteredBookings.isEmpty)
            _EmptyCard(filter: _filter)
          else
            for (final booking in filteredBookings) ...[
              _BookingCard(booking: booking),
              const SizedBox(height: 12),
            ],
        ],
      );
    },
  );
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final bookingBadge = switch (booking.bookingStatus) {
      BookingStatus.pendingPayment => badges.BookingStatus.awaitingPayment,
      BookingStatus.confirmed => badges.BookingStatus.confirmed,
      BookingStatus.checkedIn => badges.BookingStatus.checkedIn,
      BookingStatus.inProgress => badges.BookingStatus.inProgress,
      BookingStatus.completed => badges.BookingStatus.completed,
      BookingStatus.cancelled => badges.BookingStatus.cancelled,
    };
    final paymentBadge = switch (booking.paymentStatus) {
      PaymentStatus.pendingVerification =>
        badges.PaymentStatus.pendingVerification,
      PaymentStatus.verified => badges.PaymentStatus.verified,
      PaymentStatus.rejected => badges.PaymentStatus.rejected,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border(
          left: BorderSide(
            color: booking.bookingStatus == BookingStatus.confirmed
                ? AppTheme.primary
                : AppTheme.warning,
            width: 4,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withAlpha(16),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            booking.serviceName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              badges.StatusBadgeWidget.fromBookingStatus(bookingBadge),
              badges.StatusBadgeWidget.fromPaymentStatus(paymentBadge),
            ],
          ),
          const SizedBox(height: 12),
          _line('Booking ref.', booking.referenceNumber),
          _line('Clinic', 'E-Relax Massage Clinic'),
          _line('Therapist', booking.therapistName),
          _line(
            'Appointment',
            '${_date(booking.appointmentDate)} · ${booking.startTime} (${booking.durationMinutes} min)',
          ),
          _line('Total', 'PHP ${booking.totalAmount.toStringAsFixed(2)}'),
          _line(
            'Down payment',
            'PHP ${booking.paymentAmount.toStringAsFixed(2)} / PHP ${booking.requiredDownPayment.toStringAsFixed(2)}',
          ),
          _line(
            'Balance due',
            'PHP ${booking.remainingBalance.toStringAsFixed(2)} after service',
          ),
          if (booking.balancePayment case final balance?)
            _line(
              'Balance paid',
              'PHP ${balance.amount.toStringAsFixed(2)} by ${balance.method}',
            ),
          _line('Payment ref.', booking.transactionReference),
          if (booking.paymentReviewedAt != null)
            _line(
              'Reviewed',
              '${_date(booking.paymentReviewedAt!)} by ${booking.paymentReviewedBy ?? 'Admin'}',
            ),
          if (booking.paymentRejectionReason case final reason?)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Rejection reason: $reason',
                style: const TextStyle(color: AppTheme.error, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => BookingReceiptService.download(booking),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
                label: const Text('Download receipt'),
              ),
              if (booking.paymentStatus == PaymentStatus.rejected)
                FilledButton.icon(
                  onPressed: () => _resubmit(context),
                  icon: const Icon(Icons.upload_file_rounded, size: 17),
                  label: const Text('Resubmit proof'),
                ),
              OutlinedButton.icon(
                onPressed: () => _showContact(context),
                icon: const Icon(Icons.support_agent_rounded, size: 17),
                label: const Text('Contact clinic'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(
          width: 112,
          child: Text(
            '$label:',
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.onSurfaceVariantLight,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  Future<void> _resubmit(BuildContext context) async {
    final controller = TextEditingController(
      text: booking.transactionReference,
    );
    final formKey = GlobalKey<FormState>();
    Uint8List? image;
    String? fileName;
    final submission = await showDialog<_ProofDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Resubmit payment proof'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (booking.paymentRejectionReason != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Please correct: ${booking.paymentRejectionReason}',
                        style: const TextStyle(color: AppTheme.error),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    'Upload proof for the 30% down payment of PHP ${booking.requiredDownPayment.toStringAsFixed(2)}.',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Transaction reference',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter the transaction reference'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final files = await FilePicker.pickFiles(
                        type: FileType.image,
                      );
                      if (files.isEmpty) return;
                      final bytes = await files.first.readAsBytes();
                      setState(() {
                        image = bytes;
                        fileName = files.first.name;
                      });
                    },
                    icon: const Icon(Icons.upload_file),
                    label: Text(fileName ?? 'Choose corrected screenshot'),
                  ),
                  if (image != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Image.memory(
                        image!,
                        height: 110,
                        fit: BoxFit.contain,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                if (image == null || image!.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Choose a payment screenshot to continue'),
                    ),
                  );
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  _ProofDraft(controller.text.trim(), image!),
                );
              },
              child: const Text('Submit proof'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (submission == null || !context.mounted) return;
    final saved = PaymentBookingStore.instance.resubmitProof(
      booking.id,
      clientId: localClientSessionId,
      reference: submission.reference,
      screenshot: submission.image,
    );
    if (saved && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Updated proof submitted for admin verification'),
        ),
      );
    }
  }

  void _showContact(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Contact clinic'),
      content: const Text(
        'Please use the clinic contact details provided when your booking was made.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class _ProofDraft {
  const _ProofDraft(this.reference, this.image);
  final String reference;
  final Uint8List image;
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.filter});
  final _BookingFilter filter;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      filter == _BookingFilter.upcoming
          ? 'You have no upcoming appointments. Your booking and payment updates will appear here.'
          : 'You have no past appointments yet.',
    ),
  );
}
