import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../data/therapist_roster_store.dart';
import '../../../theme/app_theme.dart';

class TherapistAvatarRowWidget extends StatelessWidget {
  const TherapistAvatarRowWidget({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: TherapistRosterStore.instance,
    builder: (context, _) {
      final therapists = TherapistRosterStore.instance.therapists;
      final today = DateUtils.dateOnly(DateTime.now());

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Our Therapists',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.onSurfaceLight,
                ),
              ),
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'View All',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (therapists.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Our therapist profiles will appear here once the clinic adds them.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: AppTheme.onSurfaceVariantLight,
                ),
              ),
            )
          else
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: therapists.length,
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder: (context, index) {
                  final therapist = therapists[index];
                  final isOnDuty = TherapistRosterStore.instance.isOnDuty(
                    therapist.id,
                    today,
                  );

                  return SizedBox(
                    width: 64,
                    child: Column(
                      children: [
                        Stack(
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryContainer,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isOnDuty
                                      ? AppTheme.primary
                                      : Colors.grey.shade300,
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primary.withAlpha(31),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                                image: therapist.profileImageBytes != null
                                    ? DecorationImage(image: MemoryImage(therapist.profileImageBytes!), fit: BoxFit.cover)
                                    : (TherapistRosterStore.instance.photoUrl(therapist) == null
                                        ? null
                                        : DecorationImage(image: NetworkImage(TherapistRosterStore.instance.photoUrl(therapist)!), fit: BoxFit.cover)),
                              ),
                              child: therapist.profileImageBytes == null && TherapistRosterStore.instance.photoUrl(therapist) == null
                                  ? Center(
                                      child: Text(
                                        _initials(therapist.name),
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.primary,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                            Positioned(
                              bottom: 2,
                              right: 2,
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: isOnDuty
                                      ? AppTheme.success
                                      : Colors.grey.shade400,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          therapist.name.split(' ').first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.onSurfaceLight,
                          ),
                        ),
                        Text(
                          therapist.specialty,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w400,
                            color: AppTheme.onSurfaceVariantLight,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      );
    },
  );

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty);
    final initials = parts.take(2).map((part) => part[0].toUpperCase()).join();
    return initials.isEmpty ? '?' : initials;
  }
}
