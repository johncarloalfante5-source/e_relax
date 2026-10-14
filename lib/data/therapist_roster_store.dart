import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/booking.dart';
import '../models/therapist_profile.dart';
import 'repositories/clinic_repository.dart';
import 'repositories/supabase_clinic_repository.dart';
import 'backend/supabase_client_provider.dart';

export '../models/therapist_profile.dart';
import 'payment_booking_store.dart';

class TherapistRosterStore extends ChangeNotifier {
  TherapistRosterStore._();

  static final TherapistRosterStore instance = TherapistRosterStore._();

  final ClinicRepository _repository = SupabaseClinicRepository();
  StreamSubscription<List<TherapistProfile>>? _therapistSubscription;
  StreamSubscription<List<TherapistProfile>>? _dutySubscription;
  String? _watchingDutyDate;

  final List<TherapistProfile> _therapists = [];

  final Map<String, Set<String>> _dutyByDate = {};

  Future<void> initialize() async {
    await _therapistSubscription?.cancel();
    await refreshTherapists();
    _therapistSubscription = _repository.watchTherapists().listen((items) {
      _therapists
        ..clear()
        ..addAll(items);
      notifyListeners();
    });
  }

  Future<void> refreshTherapists() async {
    final items = await _repository.watchTherapists().first;
    _therapists
      ..clear()
      ..addAll(items);
    notifyListeners();
  }

  Future<void> refreshDuty(DateTime date) async {
    final items = await _repository.watchDutyForDate(date).first;
    _dutyByDate[_dateKey(date)] = items.map((item) => item.id).toSet();
    notifyListeners();
  }

  Future<void> watchDutyForDate(DateTime date) async {
    final key = _dateKey(date);
    await refreshDuty(date);
    if (_watchingDutyDate == key) return;
    await _dutySubscription?.cancel();
    _watchingDutyDate = key;
    _dutySubscription = _repository.watchDutyForDate(date).listen((items) {
      _dutyByDate[key] = items.map((item) => item.id).toSet();
      notifyListeners();
    });
  }

  List<TherapistProfile> get therapists => List.unmodifiable(_therapists);
  String? photoUrl(TherapistProfile therapist) {
    final path = therapist.profileImagePath;
    if (path == null || path.isEmpty) return null;
    return SupabaseClientProvider.client.storage.from('therapist-profiles').getPublicUrl(path);
  }

  TherapistProfile? findById(String id) {
    for (final therapist in _therapists) {
      if (therapist.id == id) return therapist;
    }
    return null;
  }

  TherapistProfile? findByEmail(String email) {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final therapist in _therapists) {
      if (therapist.email.trim().toLowerCase() == normalized) {
        return therapist;
      }
    }
    return null;
  }

  TherapistProfile? findByAuthProfileId(String id) {
    for (final therapist in _therapists) {
      if (therapist.authProfileId == id) return therapist;
    }
    return null;
  }

  List<TherapistProfile> onDutyForDate(DateTime date) {
    final ids = _dutyByDate[_dateKey(date)] ?? const <String>{};
    return _therapists
        .where((therapist) => ids.contains(therapist.id))
        .toList(growable: false);
  }

  bool isOnDuty(String therapistId, DateTime date) =>
      (_dutyByDate[_dateKey(date)] ?? const <String>{}).contains(therapistId);

  Future<void> setDutyForDate(DateTime date, Set<String> therapistIds) async {
    final knownIds = _therapists.map((therapist) => therapist.id).toSet();
    final selected = therapistIds.intersection(knownIds);
    await _repository.saveDuty(date, selected);
    _dutyByDate[_dateKey(date)] = selected;
    notifyListeners();
  }

  Future<TherapistProfile> addTherapist({
    required String name,
    required String specialty,
    required String email,
    required String phone,
    Uint8List? profileImageBytes,
  }) async {
    final therapist = TherapistProfile(
      id: 'th_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      specialty: specialty.trim().isEmpty
          ? 'Massage Therapist'
          : specialty.trim(),
      email: email.trim(),
      phone: phone.trim(),
      profileImageBytes: profileImageBytes,
    );
    final saved = await _repository.saveTherapist(therapist, profileImageBytes);
    _therapists.add(saved);
    notifyListeners();
    return saved;
  }

  Future<void> updateTherapist(
    String id, {
    required String name,
    required String specialty,
    required String email,
    required String phone,
    Uint8List? profileImageBytes,
  }) async {
    final therapist = findById(id);
    if (therapist == null) return;
    therapist
      ..name = name.trim()
      ..specialty = specialty.trim().isEmpty
          ? 'Massage Therapist'
          : specialty.trim()
      ..email = email.trim()
      ..phone = phone.trim()
      ..profileImageBytes = profileImageBytes;
    final saved = await _repository.saveTherapist(therapist, profileImageBytes);
    final index = _therapists.indexWhere((item) => item.id == id);
    if (index >= 0) _therapists[index] = saved;
    notifyListeners();
  }

  List<Booking> bookingsForTherapist(String therapistId) => PaymentBookingStore
      .instance
      .bookings
      .where((booking) => booking.therapistId == therapistId)
      .toList(growable: false);

  List<TherapistProfile> availableForBooking({
    required DateTime date,
    required String startTime,
    required int durationMinutes,
  }) {
    final onDuty = onDutyForDate(date);
    if (onDuty.isEmpty) return onDuty;
    final proposedStart = _minutesFromTime(startTime);
    if (proposedStart == null) return onDuty;
    final proposedEnd = proposedStart + durationMinutes;
    final bookings = PaymentBookingStore.instance.bookings;
    return onDuty
        .where((therapist) {
          return !bookings.any((booking) {
            if (booking.therapistId != therapist.id ||
                booking.bookingStatus == BookingStatus.cancelled ||
                !_sameDay(booking.appointmentDate, date)) {
              return false;
            }
            final existingStart = _minutesFromTime(booking.startTime);
            if (existingStart == null) return false;
            final existingEnd = existingStart + booking.durationMinutes;
            return proposedStart < existingEnd && existingStart < proposedEnd;
          });
        })
        .toList(growable: false);
  }

  Future<List<TherapistProfile>> availableForBookingRemote({
    required DateTime date,
    required String startTime,
    required int durationMinutes,
    required String serviceId,
  }) => _repository.availableTherapists(date: date, startTime: startTime, durationMinutes: durationMinutes, serviceId: serviceId);

  static bool _sameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static int? _minutesFromTime(String value) {
    final match = RegExp(
      r'^\s*(\d{1,2}):(\d{2})\s*(AM|PM)\s*$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null ||
        minute == null ||
        hour < 1 ||
        hour > 12 ||
        minute > 59) {
      return null;
    }
    final period = match.group(3)!.toUpperCase();
    final hour24 = (hour % 12) + (period == 'PM' ? 12 : 0);
    return hour24 * 60 + minute;
  }
}
