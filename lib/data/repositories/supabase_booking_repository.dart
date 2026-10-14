import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/booking.dart';
import '../../models/create_booking_request.dart';
import '../backend/supabase_client_provider.dart';
import 'booking_repository.dart';

class SupabaseBookingRepository implements BookingRepository {
  SupabaseClient get _client => SupabaseClientProvider.client;
  static const _bucket = 'payment-proofs';

  @override
  Stream<List<Booking>> watchForClient() {
    final uid = _client.auth.currentUser!.id;
    return _client.from('bookings').stream(primaryKey: ['id']).eq('client_id', uid)
        .asyncMap((rows) => _hydrateRows(rows));
  }

  @override
  Stream<List<Booking>> watchForStaff() => _client.from('bookings')
      .stream(primaryKey: ['id']).asyncMap((rows) => _hydrateRows(rows));

  Future<List<Booking>> _hydrateRows(List<Map<String, dynamic>> rows) async {
    final result = <Booking>[];
    for (final row in rows) {
      final submissions = await _client.from('payment_submissions').select().eq('booking_id', row['id']).order('submission_number');
      final histories = await _client.from('booking_activity').select().eq('booking_id', row['id']).order('created_at');
      final txs = await _client.from('payment_transactions').select().eq('source_id', row['id']).inFilter('source_type', ['booking_deposit','booking_balance']);
      result.add(await _bookingFrom(row, submissions, histories, txs));
    }
    result.sort((a,b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  Future<Booking> _bookingFrom(Map<String,dynamic> row, List<Map<String,dynamic>> submissions, List<Map<String,dynamic>> histories, List<Map<String,dynamic>> txs) async {
    if (submissions.isEmpty) throw StateError('Booking ${row['id']} has no payment submission.');
    final latest = submissions.last;
    Uint8List bytes;
    try {
      bytes = await _client.storage.from(_bucket).download(latest['proof_path'] as String);
    } catch (_) {
      // Assigned therapists can view their session, but only the client and
      // payment-review staff may download financial proof images.
      bytes = Uint8List(0);
    }
    final submitted = DateTime.parse(latest['submitted_at'] as String);
    final booking = Booking(
      id: row['id'] as String,
      referenceNumber: row['reference_number'] as String,
      clientId: row['client_id'] as String,
      clientName: row['client_name'] as String,
      clientPhone: row['client_phone'] as String? ?? '',
      clientEmail: row['client_email'] as String? ?? '',
      serviceId: row['service_id'] as String,
      serviceName: row['service_name'] as String,
      serviceDescription: row['service_description'] as String? ?? '',
      therapistId: row['therapist_id'] as String,
      therapistName: row['therapist_name'] as String,
      appointmentDate: DateTime.parse(row['appointment_date'] as String),
      startTime: row['start_time'] as String,
      durationMinutes: row['duration_minutes'] as int,
      totalAmount: (row['total_amount'] as num).toDouble(),
      discountAmount: (row['discount_amount'] as num).toDouble(),
      transactionReference: latest['transaction_reference'] as String,
      paymentAmount: (latest['amount'] as num).toDouble(),
      receiptImage: bytes,
      paymentSubmittedAt: submitted,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
    booking.bookingStatus = _bookingStatus(row['status'] as String);
    booking.paymentStatus = switch(latest['status'] as String) {
      'Verified' => PaymentStatus.verified,
      'Rejected' => PaymentStatus.rejected,
      _ => PaymentStatus.pendingVerification,
    };
    booking.paymentReviewedAt = latest['reviewed_at'] == null ? null : DateTime.parse(latest['reviewed_at'] as String);
    booking.paymentReviewedBy = latest['reviewed_by'] as String?;
    booking.paymentRejectionReason = latest['rejection_reason'] as String?;
    booking.updatedAt = DateTime.parse(row['updated_at'] as String);
    booking.checkedInAt = row['checked_in_at'] == null ? null : DateTime.parse(row['checked_in_at'] as String);
    booking.serviceStartedAt = row['service_started_at'] == null ? null : DateTime.parse(row['service_started_at'] as String);
    booking.serviceCompletedAt = row['service_completed_at'] == null ? null : DateTime.parse(row['service_completed_at'] as String);
    booking.cancellationReason = row['cancellation_reason'] as String?;
    booking.proofSubmissions
      ..clear()
      ..addAll(await Future.wait(submissions.map((s) async => PaymentProofSubmission(
        id: s['id'] as String,
        transactionReference: s['transaction_reference'] as String,
        amount: (s['amount'] as num).toDouble(),
        screenshot: s['id'] == latest['id'] ? bytes : Uint8List(0),
        submittedAt: DateTime.parse(s['submitted_at'] as String),
        rejectionReason: s['rejection_reason'] as String?,
        reviewedAt: s['reviewed_at'] == null ? null : DateTime.parse(s['reviewed_at'] as String),
        reviewedBy: s['reviewed_by'] as String?,
      ))));
    final deposit = txs.where((tx) => tx['source_type'] == 'booking_deposit').fold<double>(0, (s,tx) => s+(tx['amount'] as num).toDouble());
    final balance = txs.where((tx) => tx['source_type'] == 'booking_balance').toList();
    if (balance.isNotEmpty) {
      final tx = balance.last;
      booking.balancePayment = BalancePayment(amount: (tx['amount'] as num).toDouble(), method: tx['method'] as String, collectedAt: DateTime.parse(tx['captured_at'] as String), collectedBy: tx['actor_id'] as String? ?? 'staff');
    }
    if (booking.paymentStatus != PaymentStatus.verified && deposit > 0) booking.paymentAmount = 0;
    booking.activity
      ..clear()
      ..addAll(histories.map((h) => BookingActivity(type: _activityType(h['event'] as String), at: DateTime.parse(h['created_at'] as String), actor: h['actor_id'] as String? ?? 'system', note: h['note'] as String?)));
    return booking;
  }

  @override
  Future<Booking> createOnlineBooking(CreateBookingRequest request) async {
    final uid = _client.auth.currentUser!.id;
    final type = _imageType(request.proof);
    final path = '$uid/${DateTime.now().microsecondsSinceEpoch}.${type.extension}';
    await _client.storage.from(_bucket).uploadBinary(path, request.proof, fileOptions: FileOptions(contentType: type.mime, upsert: false));
    try {
      final time = _minutes(request.startTime);
      if (time == null) throw ArgumentError('Invalid appointment time.');
      final startAt = DateTime.utc(request.appointmentDate.year, request.appointmentDate.month, request.appointmentDate.day, time ~/ 60, time % 60).subtract(const Duration(hours: 8)).toIso8601String();
      final id = await _client.rpc('create_online_booking', params: {
        'p_service_id': request.serviceId,
        'p_therapist_id': request.therapistId,
        'p_appointment_date': _date(request.appointmentDate),
        'p_start_time': request.startTime,
        'p_start_at': startAt,
        'p_client_name': request.clientName,
        'p_client_phone': request.clientPhone,
        'p_client_email': request.clientEmail,
        'p_transaction_reference': request.transactionReference.trim(),
        'p_proof_path': path,
      }) as String;
      final rows = await _client.from('bookings').select().eq('id', id).single();
      return (await _hydrateRows([rows])).single;
    } catch (_) {
      await _client.storage.from(_bucket).remove([path]);
      rethrow;
    }
  }

  @override
  Future<void> verifyPayment(String submissionId) => _client.rpc('verify_payment', params: {'p_submission_id': submissionId});
  @override
  Future<void> rejectPayment(String submissionId, {required String reason}) => _client.rpc('reject_payment', params: {'p_submission_id': submissionId, 'p_reason': reason});
  @override
  Future<void> resubmitProof(String bookingId, {required String reference, required Uint8List proof}) async {
    final uid = _client.auth.currentUser!.id;
    final type = _imageType(proof);
    final path = '$uid/${DateTime.now().microsecondsSinceEpoch}.${type.extension}';
    await _client.storage.from(_bucket).uploadBinary(path, proof, fileOptions: FileOptions(contentType: type.mime));
    try {
      await _client.rpc('resubmit_payment_proof', params: {'p_booking_id': bookingId, 'p_reference': reference.trim(), 'p_path': path});
    } catch (_) {
      await _client.storage.from(_bucket).remove([path]);
      rethrow;
    }
  }

  _ProofImageType _imageType(Uint8List bytes) {
    if (bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50) {
      return const _ProofImageType('png', 'image/png');
    }
    if (bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8) {
      return const _ProofImageType('jpg', 'image/jpeg');
    }
    if (bytes.length >= 12 && bytes[0] == 0x52 && bytes[8] == 0x57) {
      return const _ProofImageType('webp', 'image/webp');
    }
    return const _ProofImageType('jpg', 'image/jpeg');
  }

  @override
  Future<void> transition(String bookingId, BookingStatus next, {String? reason}) => _client.rpc('transition_booking', params: {'p_booking_id': bookingId, 'p_status': next.name, 'p_reason': reason});
  @override
  Future<void> markNotificationRead(String notificationId) => _client.rpc('mark_notification_read', params: {'p_notification_id': notificationId});

  String _date(DateTime d) => '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  int? _minutes(String value) {
    final m=RegExp(r'^\s*(\d{1,2}):(\d{2})\s*(AM|PM)\s*$',caseSensitive:false).firstMatch(value);
    if(m==null)return null; final h=int.parse(m.group(1)!); final min=int.parse(m.group(2)!);
    if(h<1||h>12||min>59)return null; return (h%12)*60+min+(m.group(3)!.toUpperCase()=='PM'?720:0);
  }
  BookingStatus _bookingStatus(String value) => BookingStatus.values.firstWhere((s)=>s.name==value,orElse:()=>BookingStatus.pendingPayment);
  BookingActivityType _activityType(String value) => switch(value) {
    'booking_created'=>BookingActivityType.bookingCreated,
    'proof_submitted'||'proof_resubmitted'=>BookingActivityType.proofSubmitted,
    'payment_verified'=>BookingActivityType.paymentVerified,
    'payment_rejected'=>BookingActivityType.paymentRejected,
    'client_checked_in'=>BookingActivityType.clientCheckedIn,
    'service_started'=>BookingActivityType.serviceStarted,
    'service_completed'=>BookingActivityType.serviceCompleted,
    'balance_collected'=>BookingActivityType.balanceCollected,
    'booking_cancelled'=>BookingActivityType.bookingCancelled,
    _=>BookingActivityType.bookingConfirmed,
  };
}

class _ProofImageType {
  const _ProofImageType(this.extension, this.mime);
  final String extension;
  final String mime;
}
