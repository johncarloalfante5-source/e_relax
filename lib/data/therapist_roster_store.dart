import 'package:flutter/foundation.dart';

import '../models/booking.dart';
import 'payment_booking_store.dart';

class TherapistProfile {
  TherapistProfile({
    required this.id,
    required this.name,
    required this.specialty,
    this.email = '',
    this.phone = '',
    required this.imageUrl,
    required this.semanticLabel,
    required this.rating,
  });

  final String id;
  String name;
  String specialty;
  String email;
  String phone;
  final String imageUrl;
  final String semanticLabel;
  final double rating;
}

/// Local prototype roster. Persist and secure this data with the clinic backend
/// before using it across devices or for real staff scheduling.
class TherapistRosterStore extends ChangeNotifier {
  TherapistRosterStore._();

  static final TherapistRosterStore instance = TherapistRosterStore._();

  final List<TherapistProfile> _therapists = [
    TherapistProfile(
      id: 'th_001',
      name: 'Ana Reyes',
      specialty: 'Whole Body Massage',
      imageUrl: 'https://img.rocket.new/generatedImages/rocket_gen_img_19a82baf4-1767692472426.png',
      semanticLabel: 'Massage therapist in clinic uniform',
      rating: 4.9,
    ),
    TherapistProfile(
      id: 'th_002',
      name: 'Carlo Mendoza',
      specialty: 'Lying/Back Massage',
      imageUrl: 'https://img.rocket.new/generatedImages/rocket_gen_img_1b9604b34-1763299505683.png',
      semanticLabel: 'Massage therapist in clinic uniform',
      rating: 4.7,
    ),
    TherapistProfile(
      id: 'th_003',
      name: 'Liza Cruz',
      specialty: 'Foot Massage',
      imageUrl: 'https://img.rocket.new/generatedImages/rocket_gen_img_4d4c616d2-1790969275350.png',
      semanticLabel: 'Massage therapist in clinic uniform',
      rating: 4.8,
    ),
    TherapistProfile(
      id: 'th_004',
      name: 'Rico Santos',
      specialty: 'Whole Body Massage',
      imageUrl: 'https://img.rocket.new/generatedImages/rocket_gen_img_1ce99d7fe-1763293468508.png',
      semanticLabel: 'Massage therapist in clinic uniform',
      rating: 4.6,
    ),
    TherapistProfile(
      id: 'th_005',
      name: 'Grace Tan',
      specialty: 'Foot Massage',
      imageUrl: 'https://img.rocket.new/generatedImages/rocket_gen_img_4d4c616d2-1790969275350.png',
      semanticLabel: 'Massage therapist in clinic uniform',
      rating: 4.5,
    ),
  ];

  final Map<String, Set<String>> _dutyByDate = {};

  List<TherapistProfile> get therapists => List.unmodifiable(_therapists);

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

  List<TherapistProfile> onDutyForDate(DateTime date) {
    final ids = _dutyByDate[_dateKey(date)] ?? const <String>{};
    return _therapists
        .where((therapist) => ids.contains(therapist.id))
        .toList(growable: false);
  }

  bool isOnDuty(String therapistId, DateTime date) =>
      (_dutyByDate[_dateKey(date)] ?? const <String>{}).contains(therapistId);

  void setDutyForDate(DateTime date, Set<String> therapistIds) {
    final knownIds = _therapists.map((therapist) => therapist.id).toSet();
    final selected = therapistIds.intersection(knownIds);
    _dutyByDate[_dateKey(date)] = selected;
    notifyListeners();
  }

  TherapistProfile addTherapist({
    required String name,
    required String specialty,
    required String email,
    required String phone,
  }) {
    final therapist = TherapistProfile(
      id: 'th_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      specialty: specialty.trim().isEmpty
          ? 'Massage Therapist'
          : specialty.trim(),
      email: email.trim(),
      phone: phone.trim(),
      imageUrl: 'https://img.rocket.new/generatedImages/rocket_gen_img_19a82baf4-1767692472426.png',
      semanticLabel: 'Massage therapist in clinic uniform',
      rating: 5.0,
    );
    _therapists.add(therapist);
    notifyListeners();
    return therapist;
  }

  void updateTherapist(
    String id, {
    required String name,
    required String specialty,
    required String email,
    required String phone,
  }) {
    final therapist = findById(id);
    if (therapist == null) return;
    therapist
      ..name = name.trim()
      ..specialty = specialty.trim().isEmpty
          ? 'Massage Therapist'
          : specialty.trim()
      ..email = email.trim()
      ..phone = phone.trim();
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
