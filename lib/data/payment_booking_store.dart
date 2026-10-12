import 'package:flutter/foundation.dart';

import '../models/booking.dart';

/// Active prototype client identity. Replace this with the authenticated user
/// from the backend when real authentication is connected.
class ClientSession extends ChangeNotifier {
  ClientSession._();

  static final ClientSession instance = ClientSession._();
  static final Map<String, String> _knownNames = {};

  String? _email;
  String? _name;

  String get clientId =>
      _email == null ? 'local-client-session' : 'local-client:' + _email!;
  String get clientName => _name ?? 'Client';
  String? get email => _email;

  void signIn({required String email, String? displayName}) {
    final normalizedEmail = email.trim().toLowerCase();
    final submittedName = displayName?.trim();
    if (submittedName != null && submittedName.isNotEmpty) {
      _knownNames[normalizedEmail] = submittedName;
    }
    _email = normalizedEmail;
    _name = _knownNames[normalizedEmail] ?? _nameFromEmail(normalizedEmail);
    notifyListeners();
  }

  void signOut() {
    _email = null;
    _name = null;
    notifyListeners();
  }

  void updateDisplayName(String name) {
    final cleanName = name.trim();
    if (_email == null || cleanName.isEmpty) return;
    _knownNames[_email!] = cleanName;
    _name = cleanName;
    notifyListeners();
  }

  String _nameFromEmail(String email) {
    final localPart = email.split('@').first;
    final parts = localPart
        .split(RegExp(r'[._+\-]+'))
        .where((part) => part.isNotEmpty);
    final name = parts
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
    return name.isEmpty ? 'Client' : name;
  }
}

String get localClientSessionId => ClientSession.instance.clientId;
String get localClientSessionName => ClientSession.instance.clientName;

enum ClientNoticeType {
  paymentVerified,
  paymentRejected,
  proofResubmitted,
  bookingConfirmed,
  balanceCollected,
}

class ClientPaymentNotice {
  ClientPaymentNotice({
    required this.id,
    required this.clientId,
    required this.bookingId,
    required this.type,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String clientId;
  final String bookingId;
  final ClientNoticeType type;
  final String message;
  final DateTime createdAt;
  bool isRead = false;
}

/// Demo repository and notifier. Persist through an authenticated server API
/// before relying on it for real appointments or payment decisions.
class PaymentBookingStore extends ChangeNotifier {
  PaymentBookingStore();
  static final PaymentBookingStore instance = PaymentBookingStore();

  final List<Booking> _bookings = [];
  final List<ClientPaymentNotice> _notices = [];

  List<Booking> get bookings => List.unmodifiable(_bookings);
  List<ClientPaymentNotice> get notices => List.unmodifiable(_notices);
  List<Booking> get pendingBookings => _bookings
      .where(
        (booking) => booking.paymentStatus == PaymentStatus.pendingVerification,
      )
      .toList(growable: false);

  List<Booking> bookingsForClient(String clientId) => _bookings
      .where((booking) => booking.clientId == clientId)
      .toList(growable: false);

  List<ClientPaymentNotice> noticesForClient(String clientId) => _notices
      .where((notice) => notice.clientId == clientId)
      .toList(growable: false);

  int unreadNoticeCountForClient(String clientId) => _notices
      .where((notice) => notice.clientId == clientId && !notice.isRead)
      .length;

  void markNoticeRead(String noticeId, {required String clientId}) {
    for (final notice in _notices) {
      if (notice.id == noticeId && notice.clientId == clientId) {
        if (!notice.isRead) {
          notice.isRead = true;
          notifyListeners();
        }
        return;
      }
    }
  }

  void markAllNoticesRead(String clientId) {
    var changed = false;
    for (final notice in _notices) {
      if (notice.clientId == clientId && !notice.isRead) {
        notice.isRead = true;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  Booking? findById(String bookingId) {
    for (final booking in _bookings) {
      if (booking.id == bookingId) return booking;
    }
    return null;
  }

  void add(Booking booking) {
    if (findById(booking.id) != null) {
      throw StateError('A booking with this ID already exists.');
    }
    _bookings.insert(0, booking);
    notifyListeners();
  }

  bool verifyPayment(String bookingId, {required String adminId}) {
    final booking = findById(bookingId);
    if (booking == null ||
        booking.paymentStatus != PaymentStatus.pendingVerification) {
      return false;
    }
    if (booking.transactionReference.trim().isEmpty ||
        booking.paymentAmount <= 0 ||
        booking.paymentAmount != booking.requiredDownPayment ||
        booking.receiptImage.isEmpty) {
      return false;
    }

    final now = DateTime.now();
    booking
      ..paymentStatus = PaymentStatus.verified
      ..paymentReviewedAt = now
      ..paymentReviewedBy = adminId
      ..paymentRejectionReason = null
      ..updatedAt = now;
    booking.latestProof
      ..reviewedAt = now
      ..reviewedBy = adminId;
    _audit(booking, BookingActivityType.paymentVerified, adminId);
    _addNoticeOnce(
      id: 'verified:${booking.id}:${booking.proofSubmissions.length}',
      booking: booking,
      type: ClientNoticeType.paymentVerified,
      message:
          'The 30% down payment for ${booking.serviceName} was verified. Appointment: ${_date(booking.appointmentDate)} at ${booking.startTime}. Booking status: ${booking.bookingStatus.label}.',
    );
    notifyListeners();
    return true;
  }

  bool rejectPayment(
    String bookingId, {
    required String adminId,
    required String reason,
  }) {
    final booking = findById(bookingId);
    final cleanReason = reason.trim();
    if (booking == null ||
        booking.paymentStatus != PaymentStatus.pendingVerification ||
        cleanReason.isEmpty) {
      return false;
    }
    final now = DateTime.now();
    booking
      ..paymentStatus = PaymentStatus.rejected
      ..paymentReviewedAt = now
      ..paymentReviewedBy = adminId
      ..paymentRejectionReason = cleanReason
      ..updatedAt = now;
    booking.latestProof
      ..reviewedAt = now
      ..reviewedBy = adminId
      ..rejectionReason = cleanReason;
    _audit(booking, BookingActivityType.paymentRejected, adminId, cleanReason);
    _addNoticeOnce(
      id: 'rejected:${booking.id}:${booking.proofSubmissions.length}',
      booking: booking,
      type: ClientNoticeType.paymentRejected,
      message:
          'Payment proof for ${booking.serviceName} was rejected: $cleanReason',
    );
    notifyListeners();
    return true;
  }

  bool resubmitProof(
    String bookingId, {
    required String clientId,
    required String reference,
    required Uint8List screenshot,
  }) {
    final booking = findById(bookingId);
    final cleanReference = reference.trim();
    if (booking == null ||
        booking.clientId != clientId ||
        booking.paymentStatus != PaymentStatus.rejected ||
        cleanReference.isEmpty ||
        screenshot.isEmpty) {
      return false;
    }
    final now = DateTime.now();
    booking.proofSubmissions.add(
      PaymentProofSubmission(
        transactionReference: cleanReference,
        amount: booking.requiredDownPayment,
        screenshot: screenshot,
        submittedAt: now,
      ),
    );
    booking
      ..paymentStatus = PaymentStatus.pendingVerification
      ..paymentAmount = booking.requiredDownPayment
      ..paymentSubmittedAt = now
      ..paymentReviewedAt = null
      ..paymentReviewedBy = null
      ..paymentRejectionReason = null
      ..updatedAt = now;
    _audit(booking, BookingActivityType.proofSubmitted, clientId);
    _addNoticeOnce(
      id: 'resubmitted:${booking.id}:${booking.proofSubmissions.length}',
      booking: booking,
      type: ClientNoticeType.proofResubmitted,
      message:
          'Updated payment proof for ${booking.serviceName} was submitted and is awaiting review.',
    );
    notifyListeners();
    return true;
  }

  bool collectBalance(
    String bookingId, {
    required double amount,
    required String method,
    required String cashierId,
  }) {
    final booking = findById(bookingId);
    const methods = {'Cash', 'Card', 'GCash'};
    if (booking == null ||
        booking.paymentStatus != PaymentStatus.verified ||
        booking.bookingStatus != BookingStatus.completed ||
        booking.balancePayment != null ||
        booking.remainingBalance <= 0 ||
        amount != booking.remainingBalance ||
        !methods.contains(method)) {
      return false;
    }

    final now = DateTime.now();
    booking
      ..balancePayment = BalancePayment(
        amount: amount,
        method: method,
        collectedAt: now,
        collectedBy: cashierId,
      )
      ..updatedAt = now;
    _audit(booking, BookingActivityType.balanceCollected, cashierId);
    _addNoticeOnce(
      id: 'balance-collected:${booking.id}',
      booking: booking,
      type: ClientNoticeType.balanceCollected,
      message:
          'The remaining balance of PHP ${amount.toStringAsFixed(2)} for ${booking.serviceName} was collected. Your booking is paid in full.',
    );
    notifyListeners();
    return true;
  }

  bool canTransition(Booking booking, BookingStatus next) {
    return switch (booking.bookingStatus) {
      BookingStatus.pendingPayment =>
        next == BookingStatus.confirmed || next == BookingStatus.cancelled,
      BookingStatus.confirmed =>
        next == BookingStatus.checkedIn || next == BookingStatus.cancelled,
      BookingStatus.checkedIn =>
        next == BookingStatus.inProgress || next == BookingStatus.cancelled,
      BookingStatus.inProgress => next == BookingStatus.completed,
      BookingStatus.completed || BookingStatus.cancelled => false,
    };
  }

  bool transitionBooking(
    String bookingId, {
    required BookingStatus next,
    required String adminId,
    String? reason,
  }) {
    final booking = findById(bookingId);
    if (booking == null || !canTransition(booking, next)) return false;
    final cleanReason = reason?.trim();
    if (next == BookingStatus.cancelled &&
        (cleanReason == null || cleanReason.isEmpty)) {
      return false;
    }
    final now = DateTime.now();
    booking
      ..bookingStatus = next
      ..updatedAt = now;
    switch (next) {
      case BookingStatus.confirmed:
        _audit(booking, BookingActivityType.bookingConfirmed, adminId);
        _addNoticeOnce(
          id: 'booking-confirmed:${booking.id}',
          booking: booking,
          type: ClientNoticeType.bookingConfirmed,
          message:
              '${booking.serviceName} is confirmed for ${_date(booking.appointmentDate)} at ${booking.startTime}.',
        );
        break;
      case BookingStatus.checkedIn:
        booking.checkedInAt = now;
        _audit(booking, BookingActivityType.clientCheckedIn, adminId);
        break;
      case BookingStatus.inProgress:
        booking.serviceStartedAt = now;
        _audit(booking, BookingActivityType.serviceStarted, adminId);
        break;
      case BookingStatus.completed:
        booking.serviceCompletedAt = now;
        _audit(booking, BookingActivityType.serviceCompleted, adminId);
        break;
      case BookingStatus.cancelled:
        booking.cancellationReason = cleanReason;
        _audit(
          booking,
          BookingActivityType.bookingCancelled,
          adminId,
          cleanReason,
        );
        break;
      case BookingStatus.pendingPayment:
        return false;
    }
    notifyListeners();
    return true;
  }

  void _audit(
    Booking booking,
    BookingActivityType type,
    String actor, [
    String? note,
  ]) {
    booking.activity.add(
      BookingActivity(type: type, at: DateTime.now(), actor: actor, note: note),
    );
  }

  void _addNoticeOnce({
    required String id,
    required Booking booking,
    required ClientNoticeType type,
    required String message,
  }) {
    if (_notices.any((notice) => notice.id == id)) return;
    _notices.insert(
      0,
      ClientPaymentNotice(
        id: id,
        clientId: booking.clientId,
        bookingId: booking.id,
        type: type,
        message: message,
        createdAt: DateTime.now(),
      ),
    );
  }

  String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
