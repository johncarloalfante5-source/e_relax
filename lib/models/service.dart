class ClinicService {
  const ClinicService({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.durationMinutes,
    required this.category,
    required this.displayOrder,
    this.rating,
    this.imageUrl,
    this.semanticLabel,
  });

  final String id, name, description, category;
  final double price;
  final int durationMinutes, displayOrder;
  final double? rating;
  final String? imageUrl, semanticLabel;

  factory ClinicService.fromJson(Map<String, dynamic> json) => ClinicService(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    price: (json['price'] as num).toDouble(),
    durationMinutes: json['duration_minutes'] as int,
    category: json['category'] as String? ?? '',
    displayOrder: json['display_order'] as int? ?? 0,
    rating: (json['rating'] as num?)?.toDouble(),
    imageUrl: json['image_url'] as String?,
    semanticLabel: json['semantic_label'] as String?,
  );
}
