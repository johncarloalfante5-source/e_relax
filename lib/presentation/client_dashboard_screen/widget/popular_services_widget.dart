import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../data/service_catalog.dart';
import '../../../theme/app_theme.dart';
import '../../../widget/custom_image_widget.dart';
import '../../../widget/custom_icon_widget.dart';

class _ServiceModel {
  final String id;
  final String name;
  final String description;
  final int price;
  final int durationMinutes;
  final double rating;
  final String imageUrl;
  final String semanticLabel;
  final String category;

  const _ServiceModel({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.durationMinutes,
    required this.rating,
    required this.imageUrl,
    required this.semanticLabel,
    required this.category,
  });
}

class PopularServicesWidget extends StatelessWidget {
  final bool isTablet;
  final void Function(Map<String, dynamic>) onBookService;

  const PopularServicesWidget({
    super.key,
    required this.isTablet,
    required this.onBookService,
  });

  static List<Map<String, dynamic>> get _serviceMaps => ServiceCatalog.services;

  @override
  Widget build(BuildContext context) {
    final services = _serviceMaps
        .map(
          (m) => _ServiceModel(
            id: m['id'] as String,
            name: m['name'] as String,
            description: m['description'] as String,
            price: (m['price'] as num).toInt(),
            durationMinutes: m['durationMinutes'] as int,
            rating: (m['rating'] as num).toDouble(),
            imageUrl: m['imageUrl'] as String,
            semanticLabel: m['semanticLabel'] as String,
            category: m['category'] as String,
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
              'Popular Services',
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
                'See All',
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
        isTablet
            ? LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1200 ? 3 : 2;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 350,
                    ),
                    itemCount: services.length,
                    itemBuilder: (context, i) => _ServiceCardWidget(
                      service: services[i],
                      imageHeight: 220,
                      onBook: () => onBookService(_serviceMaps[i]),
                    ),
                  );
                },
              )
            : SizedBox(
                height: 260,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: services.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) => SizedBox(
                    width: 200,
                    child: _ServiceCardWidget(
                      service: services[i],
                      imageHeight: 150,
                      onBook: () => onBookService(_serviceMaps[i]),
                    ),
                  ),
                ),
              ),
      ],
    );
  }
}

class _ServiceCardWidget extends StatelessWidget {
  final _ServiceModel service;
  final double imageHeight;
  final VoidCallback onBook;

  const _ServiceCardWidget({
    required this.service,
    required this.imageHeight,
    required this.onBook,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        // Gradient Accent card — left border gradient
        border: Border(left: BorderSide(color: AppTheme.primary, width: 3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onBook,
          borderRadius: BorderRadius.circular(18),
          splashColor: AppTheme.primary.withAlpha(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image top
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                ),
                child: Stack(
                  children: [
                    CustomImageWidget(
                      imageUrl: service.imageUrl,
                      width: double.infinity,
                      height: imageHeight,
                      fit: BoxFit.cover,
                      semanticLabel: service.semanticLabel,
                      errorWidget: _ServiceImageFallback(
                        category: service.category,
                        height: imageHeight,
                      ),
                    ),
                    // Category badge
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.secondary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          service.category,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.onSurfaceLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        CustomIconWidget(
                          iconName: 'schedule',
                          color: AppTheme.onSurfaceVariantLight,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${service.durationMinutes} min',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: AppTheme.onSurfaceVariantLight,
                          ),
                        ),
                        const SizedBox(width: 8),
                        CustomIconWidget(
                          iconName: 'star',
                          color: AppTheme.secondary,
                          size: 12,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          service.rating.toStringAsFixed(1),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.secondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '₱${service.price}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primary,
                            fontFeatures: [const FontFeature.tabularFigures()],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Book',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceImageFallback extends StatelessWidget {
  const _ServiceImageFallback({required this.category, required this.height});

  final String category;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    width: double.infinity,
    color: AppTheme.primaryContainer,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          left: 20,
          top: 18,
          child: Icon(
            category == 'Foot' ? Icons.spa_outlined : Icons.self_improvement,
            size: height * 0.55,
            color: AppTheme.primary.withAlpha(28),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              category == 'Foot' ? Icons.spa_outlined : Icons.spa_rounded,
              size: 38,
              color: AppTheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              '$category massage',
              style: GoogleFonts.plusJakartaSans(
                color: AppTheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
