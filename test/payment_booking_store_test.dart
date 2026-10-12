import 'dart:typed_data';

import 'package:e_relax/data/payment_booking_store.dart';
import 'package:e_relax/models/booking.dart';
import 'package:flutter_test/flutter_test.dart';

Booking _booking() => Booking(
  id: 'ER-test-1',
  referenceNumber: 'ER-test-1',
  clientId: localClientSessionId,
  clientName: localClientSessionName,
  serviceId: 'svc-1',
  serviceName: 'Swedish Relaxation',
  therapistId: 'th_001',
  therapistName: 'Ana Reyes',
  appointmentDate: DateTime(2026, 10, 20),
  startTime: '2:00 PM',
  durationMinutes: 60,
  totalAmount: 850,
  transactionReference: 'REF-001',
  paymentAmount: Booking.calculateDownPayment(850),
  receiptImage: Uint8List.fromList([1, 2, 3]),
  paymentSubmittedAt: DateTime(2026, 10, 10),
  createdAt: DateTime(2026, 10, 10),
);

void main() {
  group('booking and payment workflow', () {
    test(
      'payment verification is idempotent and independent of booking status',
      () {
        final store = PaymentBookingStore()..add(_booking());

        expect(store.verifyPayment('ER-test-1', adminId: 'admin-7'), isTrue);
        expect(store.verifyPayment('ER-test-1', adminId: 'admin-7'), isFalse);
        final booking = store.findById('ER-test-1')!;
        expect(booking.paymentStatus, PaymentStatus.verified);
        expect(booking.bookingStatus, BookingStatus.pendingPayment);
        expect(booking.paymentReviewedBy, 'admin-7');
        expect(store.noticesForClient(localClientSessionId), hasLength(1));
      },
    );

    test(
      'rejection requires reason and resubmission preserves proof audit',
      () {
        final store = PaymentBookingStore()..add(_booking());
        expect(
          store.rejectPayment('ER-test-1', adminId: 'admin-7', reason: '  '),
          isFalse,
        );
        expect(
          store.rejectPayment(
            'ER-test-1',
            adminId: 'admin-7',
            reason: 'Amount is unreadable',
          ),
          isTrue,
        );

        final booking = store.findById('ER-test-1')!;
        expect(booking.paymentStatus, PaymentStatus.rejected);
        expect(booking.bookingStatus, BookingStatus.pendingPayment);
        expect(booking.paymentRejectionReason, 'Amount is unreadable');
        expect(
          store.resubmitProof(
            'ER-test-1',
            clientId: 'someone-else',
            reference: 'REF-002',
            screenshot: Uint8List.fromList([4]),
          ),
          isFalse,
        );
        expect(
          store.resubmitProof(
            'ER-test-1',
            clientId: localClientSessionId,
            reference: 'REF-002',
            screenshot: Uint8List.fromList([4, 5]),
          ),
          isTrue,
        );

        expect(booking.paymentStatus, PaymentStatus.pendingVerification);
        expect(booking.proofSubmissions, hasLength(2));
        expect(booking.transactionReference, 'REF-002');
        expect(
          booking.proofSubmissions.first.rejectionReason,
          'Amount is unreadable',
        );
        expect(store.pendingBookings, contains(booking));
      },
    );

    test(
      'booking lifecycle prevents duplicate check-in and invalid completion',
      () {
        final store = PaymentBookingStore()..add(_booking());
        final booking = store.findById('ER-test-1')!;
        expect(
          store.transitionBooking(
            booking.id,
            next: BookingStatus.completed,
            adminId: 'admin',
          ),
          isFalse,
        );
        expect(
          store.transitionBooking(
            booking.id,
            next: BookingStatus.confirmed,
            adminId: 'admin',
          ),
          isTrue,
        );
        expect(
          store.transitionBooking(
            booking.id,
            next: BookingStatus.checkedIn,
            adminId: 'admin',
          ),
          isTrue,
        );
        final checkedInAt = booking.checkedInAt;
        expect(
          store.transitionBooking(
            booking.id,
            next: BookingStatus.checkedIn,
            adminId: 'admin',
          ),
          isFalse,
        );
        expect(booking.checkedInAt, checkedInAt);
        expect(
          store.transitionBooking(
            booking.id,
            next: BookingStatus.inProgress,
            adminId: 'admin',
          ),
          isTrue,
        );
        expect(
          store.transitionBooking(
            booking.id,
            next: BookingStatus.completed,
            adminId: 'admin',
          ),
          isTrue,
        );
        expect(
          booking.activity.last.type,
          BookingActivityType.serviceCompleted,
        );
      },
    );
  });
}
