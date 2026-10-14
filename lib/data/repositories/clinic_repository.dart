import 'dart:typed_data';

import '../../models/service.dart';
import '../../models/therapist_profile.dart';

abstract interface class ClinicRepository {
  Stream<List<ClinicService>> watchServices();
  Stream<List<TherapistProfile>> watchTherapists();
  Stream<List<TherapistProfile>> watchDutyForDate(DateTime date);
  Future<TherapistProfile> saveTherapist(TherapistProfile profile, Uint8List? photo);
  Future<void> saveDuty(DateTime date, Set<String> therapistIds);
  Future<List<TherapistProfile>> availableTherapists({required DateTime date, required String startTime, required int durationMinutes, required String serviceId});
}
