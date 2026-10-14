import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/booking.dart';
import '../models/create_booking_request.dart';
import 'backend/supabase_client_provider.dart';
import 'repositories/supabase_booking_repository.dart';
import 'stores/auth_session_store.dart';

/// Small view adapter for the authenticated Supabase profile.
class ClientSession extends ChangeNotifier {
  ClientSession._();

  static final ClientSession instance = ClientSession._();
  static final Map<String, String> _knownNames = {};

  String? _email;
  String? _name;
  String? _id;

  String get clientId => _id ?? (_email == null ? 'local-client-session' : 'local-client:' + _email!);
  String get clientName => _name ?? 'Client';
  String? get email => _email;

  void signIn({required String? email, String? displayName, String? clientId}) {
    final normalizedEmail = email?.trim().toLowerCase() ?? '';
    final submittedName = displayName?.trim();
    if (submittedName != null && submittedName.isNotEmpty) {
      if (normalizedEmail.isNotEmpty) _knownNames[normalizedEmail] = submittedName;
    }
    _email = normalizedEmail.isEmpty ? null : normalizedEmail;
    _id = clientId;
    _name = _knownNames[normalizedEmail] ?? submittedName ??
        (normalizedEmail.isEmpty ? 'Client' : _nameFromEmail(normalizedEmail));
    notifyListeners();
  }

  void signOut() {
    _email = null;
    _name = null;
    _id = null;
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
  bookingCancelled,
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

/// Notifier backed by the authenticated booking and notification repositories.
class PaymentBookingStore extends ChangeNotifier {
  PaymentBookingStore();
  static final PaymentBookingStore instance = PaymentBookingStore();

  final List<Booking> _bookings = [];
  final List<ClientPaymentNotice> _notices = [];
  final _repository = SupabaseBookingRepository();
  StreamSubscription<List<Booking>>? _bookingSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _noticeSubscription;

  Future<void> initialize() async {
    final profile = AuthSessionStore.instance.profile;
    if (profile == null) return;
    await _bookingSubscription?.cancel();
    final bookingStream = profile.role.name == 'client'
        ? _repository.watchForClient()
        : _repository.watchForStaff();
    _bookingSubscription = bookingStream.listen((items) {
      _bookings
        ..clear()
        ..addAll(items);
      notifyListeners();
    }, onError: (Object error) {
      _loadError = error.toString();
      notifyListeners();
    });
    await _noticeSubscription?.cancel();
    final userId = SupabaseClientProvider.client.auth.currentUser!.id;
    final initialNotices = await SupabaseClientProvider.client
        .from('notifications').select().eq('user_id', userId).order('created_at', ascending: false);
    _replaceNotices(initialNotices);
    _noticeSubscription = SupabaseClientProvider.client.from('notifications')
        .stream(primaryKey: ['id']).eq('user_id', userId).listen(_replaceNotices,
          onError: (Object error) { _loadError = error.toString(); notifyListeners(); });
  }

  Future<void> clearSession() async {
    await _bookingSubscription?.cancel();
    await _noticeSubscription?.cancel();
    _bookingSubscription = null;
    _noticeSubscription = null;
    _bookings.clear();
    _notices.clear();
    notifyListeners();
  }

  String? _loadError;
  String? get loadError => _loadError;

  void _replaceNotices(List<Map<String, dynamic>> rows) {
    _notices
      ..clear()
      ..addAll(rows.map((row) {
        final key = row['event_key'] as String? ?? '';
        final type = key.startsWith('payment_verified') ? ClientNoticeType.paymentVerified
            : key.startsWith('payment_rejected') ? ClientNoticeType.paymentRejected
            : key.startsWith('proof_resubmitted') ? ClientNoticeType.proofResubmitted
            : key.startsWith('balance_collected') ? ClientNoticeType.balanceCollected
            : key.startsWith('booking_cancelled') ? ClientNoticeType.bookingCancelled
            : ClientNoticeType.bookingConfirmed;
        final notice = ClientPaymentNotice(id: row['id'] as String,
          clientId: row['user_id'] as String, bookingId: row['booking_id'] as String? ?? '',
          type: type, message: '${row['title']}: ${row['message']}',
          createdAt: DateTime.parse(row['created_at'] as String));
        notice.isRead = row['read_at'] != null;
        return notice;
      }));
    notifyListeners();
  }

  Future<void> refresh() async {
    final profile = AuthSessionStore.instance.profile;
    if (profile == null) return;
    final stream = profile.role.name == 'client' ? _repository.watchForClient() : _repository.watchForStaff();
    final items = await stream.first;
    _bookings..clear()..addAll(items);
    notifyListeners();
  }

  Future<Booking> createOnlineBooking(CreateBookingRequest request) async {
    final booking = await _repository.createOnlineBooking(request);
    _bookings.insert(0, booking);
    notifyListeners();
    return booking;
  }

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

  Future<void> markNoticeRead(String noticeId, {required String clientId}) async {
    for (final notice in _notices) {
      if (notice.id == noticeId && notice.clientId == clientId) {
        if (!notice.isRead) {
          await _repository.markNotificationRead(noticeId);
          notice.isRead = true;
          notifyListeners();
        }
        return;
      }
    }
  }

  Future<void> markAllNoticesRead(String clientId) async {
    for (final notice in _notices.where((item) => item.clientId == clientId && !item.isRead)) {
      await _repository.markNotificationRead(notice.id);
      notice.isRead = true;
    }
    notifyListeners();
  }

  Booking? findById(String bookingId) {
    for (final booking in _bookings) {
      if (booking.id == bookingId) return booking;
    }
    return null;
  }

  Future<bool> verifyPayment(String bookingId, {required String adminId}) async {
    final booking = findById(bookingId);
    if (booking == null || booking.latestProof.id == null ||
        booking.paymentStatus != PaymentStatus.pendingVerification) {
      return false;
    }
    if (booking.transactionReference.trim().isEmpty ||
        booking.paymentAmount <= 0 ||
        booking.paymentAmount != booking.requiredDownPayment ||
        booking.receiptImage.isEmpty) {
      return false;
    }

    try {
      await _repository.verifyPayment(booking.latestProof.id!);
      await refresh();
      return true;
    } catch (error) { _loadError = error.toString(); notifyListeners(); return false; }
  }

  Future<bool> rejectPayment(
    String bookingId, {
    required String adminId,
    required String reason,
  }) async {
    final booking = findById(bookingId);
    final cleanReason = reason.trim();
    if (booking == null || booking.latestProof.id == null ||
        booking.paymentStatus != PaymentStatus.pendingVerification ||
        cleanReason.isEmpty) {
      return false;
    }
    try {
      await _repository.rejectPayment(booking.latestProof.id!, reason: cleanReason);
      await refresh();
      return true;
    } catch (error) { _loadError = error.toString(); notifyListeners(); return false; }
  }

  Future<bool> resubmitProof(
    String bookingId, {
    required String clientId,
    required String reference,
    required Uint8List screenshot,
  }) async {
    final booking = findById(bookingId);
    final cleanReference = reference.trim();
    if (booking == null ||
        booking.clientId != clientId ||
        booking.paymentStatus != PaymentStatus.rejected ||
        cleanReference.isEmpty ||
        screenshot.isEmpty) {
      return false;
    }
    try {
      await _repository.resubmitProof(bookingId, reference: cleanReference, proof: screenshot);
      await refresh();
      return true;
    } catch (error) { _loadError = error.toString(); notifyListeners(); return false; }
  }

  Future<bool> collectBalance(
    String bookingId, {
    required double amount,
    required String method,
    required String cashierId,
  }) async {
    final booking = findById(bookingId);
    const methods = {'Cash', 'Card', 'GCash'};
    if (booking == null ||
        booking.paymentStatus != PaymentStatus.verified ||
        !{
          BookingStatus.checkedIn,
          BookingStatus.inProgress,
          BookingStatus.completed,
        }.contains(booking.bookingStatus) ||
        booking.balancePayment != null ||
        booking.remainingBalance <= 0 ||
        amount != booking.remainingBalance ||
        !methods.contains(method)) {
      return false;
    }

    try {
      await SupabaseClientProvider.client.rpc(
        'collect_online_balance',
        params: {'p_booking_id': bookingId, 'p_method': method},
      );
    } catch (error) {
      _loadError = error.toString();
      notifyListeners();
      return false;
    }

    // The RPC has committed the payment. Reflect that success immediately so a
    // subsequent realtime/read refresh failure cannot report a failed payment
    // or leave the cashier able to submit the collection again.
    booking.balancePayment = BalancePayment(
      amount: amount,
      method: method,
      collectedAt: DateTime.now().toUtc(),
      collectedBy: cashierId,
    );
    booking.activity.add(
      BookingActivity(
        type: BookingActivityType.balanceCollected,
        at: booking.balancePayment!.collectedAt,
        actor: cashierId,
        note: method,
      ),
    );
    notifyListeners();

    try {
      await refresh();
    } catch (error) {
      // Keep the successful payment state in memory; a later stream update or
      // screen reload can synchronize the rest of the booking data.
      _loadError = error.toString();
      notifyListeners();
    }
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

  Future<bool> transitionBooking(
    String bookingId, {
    required BookingStatus next,
    required String adminId,
    String? reason,
  }) async {
    final booking = findById(bookingId);
    if (booking == null || !canTransition(booking, next)) return false;
    final cleanReason = reason?.trim();
    if (next == BookingStatus.cancelled &&
        (cleanReason == null || cleanReason.isEmpty)) {
      return false;
    }
    try {
      await _repository.transition(bookingId, next, reason: cleanReason);
      await refresh();
      return true;
    } catch (error) { _loadError = error.toString(); notifyListeners(); return false; }
  }

  Future<bool> cancelClientBooking(String bookingId) async {
    final booking = findById(bookingId);
    if (booking == null ||
        booking.bookingStatus != BookingStatus.confirmed ||
        booking.paymentStatus != PaymentStatus.verified) {
      return false;
    }

    try {
      await _repository.cancelClientBooking(bookingId);
    } catch (error) {
      _loadError = error.toString();
      notifyListeners();
      return false;
    }

    booking.bookingStatus = BookingStatus.cancelled;
    booking.cancellationReason =
        'Cancelled by client. Down payment is non-refundable; no refund issued.';
    booking.updatedAt = DateTime.now().toUtc();
    _audit(
      booking,
      BookingActivityType.bookingCancelled,
      ClientSession.instance.clientName,
      booking.cancellationReason,
    );
    notifyListeners();

    try {
      await refresh();
    } catch (error) {
      // The server already confirmed cancellation; keep that state visible.
      _loadError = error.toString();
      notifyListeners();
    }
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
