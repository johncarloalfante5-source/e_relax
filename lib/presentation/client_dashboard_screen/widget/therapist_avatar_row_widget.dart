import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../widget/custom_image_widget.dart';

class _TherapistModel {
  final String id;
  final String name;
  final String specialty;
  final String imageUrl;
  final String semanticLabel;
  final bool isAvailable;
  final double rating;

  const _TherapistModel({
    required this.id,
    required this.name,
    required this.specialty,
    required this.imageUrl,
    required this.semanticLabel,
    required this.isAvailable,
    required this.rating,
  });
}

class TherapistAvatarRowWidget extends StatelessWidget {
  const TherapistAvatarRowWidget({super.key});

  // TODO: Replace with real Firebase therapist data
  static const List<Map<String, dynamic>> _therapistMaps = [
    {
      'id': 'th_001',
      'name': 'Ana Reyes',
      'specialty': 'Swedish',
      'imageUrl':
          'https://img.rocket.new/generatedImages/rocket_gen_img_19a82baf4-1767692472426.png',
      'semanticLabel':
          'Filipino female massage therapist in white uniform smiling warmly',
      'isAvailable': true,
      'rating': 4.9,
    },
    {
      'id': 'th_002',
      'name': 'Carlo Mendoza',
      'specialty': 'Deep Tissue',
      'imageUrl':
          'https://img.rocket.new/generatedImages/rocket_gen_img_1b9604b34-1763299505683.png',
      'semanticLabel':
          'Male Filipino therapist in green scrubs with professional demeanor',
      'isAvailable': true,
      'rating': 4.7,
    },
    {
      'id': 'th_003',
      'name': 'Liza Cruz',
      'specialty': 'Hot Stone',
      'imageUrl':
          'https://img.rocket.new/generatedImages/rocket_gen_img_4d4c616d2-1790969275350.png',
      'semanticLabel':
          'Female therapist in white coat standing in spa treatment room',
      'isAvailable': false,
      'rating': 4.8,
    },
    {
      'id': 'th_004',
      'name': 'Rico Santos',
      'specialty': 'Shiatsu',
      'imageUrl':
          'https://img.rocket.new/generatedImages/rocket_gen_img_1ce99d7fe-1763293468508.png',
      'semanticLabel':
          'Male massage therapist in clinic uniform with confident expression',
      'isAvailable': true,
      'rating': 4.6,
    },
    {
      'id': 'th_005',
      'name': 'Grace Tan',
      'specialty': 'Aromatherapy',
      'imageUrl':
          'https://img.rocket.new/generatedImages/rocket_gen_img_4d4c616d2-1790969275350.png',
      'semanticLabel':
          'Female wellness therapist with professional appearance in spa setting',
      'isAvailable': true,
      'rating': 4.5,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final therapists = _therapistMaps
        .map(
          (m) => _TherapistModel(
            id: m['id'] as String,
            name: m['name'] as String,
            specialty: m['specialty'] as String,
            imageUrl: m['imageUrl'] as String,
            semanticLabel: m['semanticLabel'] as String,
            isAvailable: m['isAvailable'] as bool,
            rating: (m['rating'] as num).toDouble(),
          ),
        )
        .toList();

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
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: therapists.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, i) {
              final t = therapists[i];
              return GestureDetector(
                onTap: () {},
                child: Column(
                  children: [
                    Stack(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: t.isAvailable
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
                          ),
                          child: ClipOval(
                            child: CustomImageWidget(
                              imageUrl: t.imageUrl,
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                              semanticLabel: t.semanticLabel,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: t.isAvailable
                                  ? AppTheme.success
                                  : Colors.grey.shade400,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.name.split(' ').first,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onSurfaceLight,
                      ),
                    ),
                    Text(
                      t.specialty,
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
  }
}
