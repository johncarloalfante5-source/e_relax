/// Shared service catalog used by online booking and cashier walk-ins.
abstract final class ServiceCatalog {
  static const List<Map<String, dynamic>> services = [
    {
      'id': 'svc_001',
      'name': 'Whole Body Massage',
      'description':
          'A full-body relaxation massage covering all major muscle groups for complete stress relief and rejuvenation.',
      'price': 350,
      'durationMinutes': 60,
      'rating': 4.9,
      'imageUrl':
          'https://img.rocket.new/generatedImages/rocket_gen_img_13f957847-1772520779967.png',
      'semanticLabel':
          'Therapist performing full body massage on client lying on white table with soft lighting',
      'category': 'Full Body',
    },
    {
      'id': 'svc_002',
      'name': 'Lying/Back Massage',
      'description':
          'Focused back and lying massage targeting tension in the back, shoulders, and neck for quick relief.',
      'price': 180,
      'durationMinutes': 30,
      'rating': 4.8,
      'imageUrl':
          'https://img.rocket.new/generatedImages/rocket_gen_img_14dceb6ca-1767700592429.png',
      'semanticLabel':
          'Back massage being performed on client lying face down in spa setting',
      'category': 'Back',
    },
    {
      'id': 'svc_003',
      'name': 'Foot Massage',
      'description':
          'A comprehensive foot massage using reflexology techniques to relieve fatigue and improve circulation throughout the body.',
      'price': 350,
      'durationMinutes': 60,
      'rating': 4.7,
      'imageUrl':
          'https://img.rocket.new/generatedImages/rocket_gen_img_48b189a0c-1789227680293.png',
      'semanticLabel':
          'Therapist performing relaxing foot massage on client feet in spa environment',
      'category': 'Foot',
    },
    {
      'id': 'svc_004',
      'name': 'Foot Massage',
      'description':
          'A focused foot massage session targeting pressure points to relieve stress and restore energy balance.',
      'price': 180,
      'durationMinutes': 30,
      'rating': 4.6,
      'imageUrl':
          'https://img.rocket.new/generatedImages/rocket_gen_img_4f02899be-1790507336525.png',
      'semanticLabel':
          'Foot reflexology massage with therapist applying pressure to sole of client foot',
      'category': 'Foot',
    },
  ];
}
