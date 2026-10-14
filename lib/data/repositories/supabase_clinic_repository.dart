import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/booking.dart';
import '../../models/service.dart';
import '../../models/therapist_profile.dart';
import '../backend/supabase_client_provider.dart';
import '../stores/auth_session_store.dart';
import 'clinic_repository.dart';

class SupabaseClinicRepository implements ClinicRepository {
  SupabaseClient get _client => SupabaseClientProvider.client;
  String _day(DateTime d) => '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  @override
  Stream<List<ClinicService>> watchServices() => _client.from('services').stream(primaryKey: ['id']).order('display_order').map((rows) => rows.map(ClinicService.fromJson).toList());

  @override
  Stream<List<TherapistProfile>> watchTherapists() {
    final role = AuthSessionStore.instance.profile?.role.name;
    if (role == null) {
      // Startup and signed-out screens need the public directory once, but
      // the realtime change-token table is intentionally auth-only.
      return Stream<List<TherapistProfile>>.fromFuture(_loadPublicTherapists());
    }
    if (role == 'admin' || role == 'therapist') {
      return _client.from('therapists').stream(primaryKey: ['id']).order('name')
          .map((rows) => rows.map(TherapistProfile.fromJson).toList());
    }
    // Realtime cannot subscribe to SQL views. Listen to the sanitized change
    // token table, then reload the view which excludes email and contact data.
    return _client.from('therapist_directory_events')
        .stream(primaryKey: ['therapist_id'])
        .asyncMap((_) => _loadPublicTherapists());
  }

  Future<List<TherapistProfile>> _loadPublicTherapists() async {
    final rows = await _client.from('clinic_therapists').select().order('name');
    return rows.map(TherapistProfile.fromJson).toList();
  }

  @override
  Stream<List<TherapistProfile>> watchDutyForDate(DateTime date) => _client.from('therapist_duty').stream(primaryKey: ['id']).eq('work_date', _day(date)).asyncMap((rows) async {
    final ids = rows.map((row) => row['therapist_id'] as String).toList();
    if (ids.isEmpty) return <TherapistProfile>[];
    final therapists = await _client.from('clinic_therapists').select().inFilter('id', ids);
    return therapists.map(TherapistProfile.fromJson).toList();
  });

  @override
  Future<TherapistProfile> saveTherapist(TherapistProfile profile, Uint8List? photo) async {
    var path = profile.profileImagePath;
    final rowId = profile.id.startsWith('th_') ? null : profile.id;
    if (photo != null) {
      final mime = _imageMime(photo);
      final extension = mime == 'image/png' ? 'png' : mime == 'image/webp' ? 'webp' : 'jpg';
      final storagePath = '${DateTime.now().microsecondsSinceEpoch}.$extension';
      await _client.storage.from('therapist-profiles').uploadBinary(storagePath, photo, fileOptions: FileOptions(upsert: true, contentType: mime));
      path = storagePath;
    }
    final data = <String, dynamic>{
      if (rowId != null) 'id': rowId,
      'name': profile.name.trim(),
      'email': profile.email.trim().isEmpty ? null : profile.email.trim(),
      'phone': profile.phone.trim().isEmpty ? null : profile.phone.trim(),
      'specialty_service_id': _serviceIdForName(profile.specialty),
      'profile_image_path': path,
      'active': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      final saved = await _client.from('therapists').upsert(data).select().single();
      final oldPath = profile.profileImagePath;
      if (photo != null && oldPath != null && oldPath != path) {
        await _client.storage.from('therapist-profiles').remove([oldPath]);
      }
      return TherapistProfile.fromJson(saved, bytes: photo ?? profile.profileImageBytes);
    } catch (_) {
      if (photo != null && path != null) {
        await _client.storage.from('therapist-profiles').remove([path]);
      }
      rethrow;
    }
  }

  @override
  Future<void> saveDuty(DateTime date, Set<String> therapistIds) async {
    await _client.rpc('save_therapist_duty',params:{'p_work_date':_day(date),'p_therapist_ids':therapistIds.toList()});
  }

  @override
  Future<List<TherapistProfile>> availableTherapists({required DateTime date, required String startTime, required int durationMinutes, required String serviceId}) async {
    final start = _parseMinutes(startTime);
    if (start == null) return [];
    final at = DateTime.utc(date.year,date.month,date.day,start~/60,start%60).subtract(const Duration(hours: 8)).toIso8601String();
    final rows = await _client.rpc('available_therapists', params: {'p_date':_day(date),'p_start_at':at,'p_duration':durationMinutes,'p_service_id':serviceId}) as List;
    return rows.cast<Map<String,dynamic>>().map(TherapistProfile.fromJson).toList();
  }

  int? _parseMinutes(String value) {
    final m = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*(AM|PM)\s*$', caseSensitive: false).firstMatch(value);
    if (m == null) return null;
    final hour = int.parse(m.group(1)!); final minute = int.parse(m.group(2)!);
    if (hour < 1 || hour > 12 || minute > 59) return null;
    return (hour % 12) * 60 + minute + (m.group(3)!.toUpperCase() == 'PM' ? 720 : 0);
  }

  String _serviceIdForName(String name) => switch (name) {
    'Whole Body Massage' => 'svc_001',
    'Lying/Back Massage' => 'svc_002',
    'Foot Massage' => 'svc_003',
    _ => throw ArgumentError('Choose an existing massage service specialty.'),
  };

  String _imageMime(Uint8List bytes) {
    if (bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50) return 'image/png';
    if (bytes.length >= 12 && bytes[0] == 0x52 && bytes[8] == 0x57) return 'image/webp';
    return 'image/jpeg';
  }

  String therapistPhotoUrl(String path) => _client.storage.from('therapist-profiles').getPublicUrl(path);
}
