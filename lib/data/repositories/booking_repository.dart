import 'dart:typed_data';

import '../../models/booking.dart';
import '../../models/create_booking_request.dart';

abstract interface class BookingRepository {
  Stream<List<Booking>> watchForClient();
  Stream<List<Booking>> watchForStaff();
  Future<Booking> createOnlineBooking(CreateBookingRequest request);
  Future<void> verifyPayment(String submissionId);
  Future<void> rejectPayment(String submissionId, {required String reason});
  Future<void> resubmitProof(String bookingId, {required String reference, required Uint8List proof});
  Future<void> transition(String bookingId, BookingStatus next, {String? reason});
  Future<void> cancelClientBooking(String bookingId);
  Future<void> markNotificationRead(String notificationId);
}
