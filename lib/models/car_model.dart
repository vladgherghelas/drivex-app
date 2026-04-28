class CarModel {
  final String id;
  final String name;
  final String brand;
  final String category;
  final int pricePerDay;
  final String imageUrl;
  final List<String> galleryUrls;
  final int seats;
  final String? power;
  final String drive;
  final int? rangeKm;
  final List<String> features;
  final String? description;
  final double rating;
  final int reviewCount;
  final bool isAvailable;
  final String? badge;
  final String? engineType;

  // Extended spec fields
  final int? year;
  final String? fuelType;
  final String? color;
  final String? transmission;
  final String? bodyType;

  const CarModel({
    required this.id,
    required this.name,
    required this.brand,
    required this.category,
    required this.pricePerDay,
    required this.imageUrl,
    this.galleryUrls = const [],
    this.seats = 4,
    this.power,
    this.drive = 'AWD',
    this.rangeKm,
    this.features = const [],
    this.description,
    this.rating = 4.5,
    this.reviewCount = 0,
    this.isAvailable = true,
    this.badge,
    this.engineType,
    this.year,
    this.fuelType,
    this.color,
    this.transmission,
    this.bodyType,
  });

  factory CarModel.fromMap(Map<String, dynamic> map) {
    return CarModel(
      id: map['id'] as String,
      name: map['name'] as String,
      brand: map['brand'] as String,
      category: map['category'] as String,
      pricePerDay: map['price_per_day'] as int,
      imageUrl: (map['image_url'] as String?) ?? '',
      galleryUrls: (map['gallery_urls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      seats: map['seats'] as int? ?? 4,
      power: map['power'] as String?,
      drive: map['drive'] as String? ?? 'AWD',
      rangeKm: map['range_km'] as int?,
      features: (map['features'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      description: map['description'] as String?,
      rating: (map['rating'] as num?)?.toDouble() ?? 4.5,
      reviewCount: map['review_count'] as int? ?? 0,
      isAvailable: map['is_available'] as bool? ?? true,
      badge: map['badge'] as String?,
      engineType: map['engine_type'] as String?,
      year: map['year'] as int?,
      fuelType: map['fuel_type'] as String?,
      color: map['color'] as String?,
      transmission: map['transmission'] as String?,
      bodyType: map['body_type'] as String?,
    );
  }

  String get displayName => '$brand $name';
  String get priceLabel => '\$$pricePerDay/day';

  /// Icon for the engine type
  String get engineIcon {
    final t = (engineType ?? '').toLowerCase();
    if (t.contains('electric')) return '⚡';
    if (t.contains('hybrid')) return '🔋';
    if (t.contains('diesel')) return '🛢️';
    return '⛽';
  }
}
