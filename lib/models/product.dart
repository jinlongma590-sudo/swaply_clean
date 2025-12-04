// lib/models/product.dart
class Product {
  final String id;
  final String title;
  final double price;
  final String location;
  final String category;
  final String condition;
  final String description;
  final List<String> images;
  final Map<String, String> specifications;
  final Seller seller;
  final String phoneNumber;
  final String whatsappNumber;
  final DateTime postedAt;

  Product({
    required this.id,
    required this.title,
    required this.price,
    required this.location,
    required this.category,
    required this.condition,
    required this.description,
    required this.images,
    required this.specifications,
    required this.seller,
    required this.phoneNumber,
    required this.whatsappNumber,
    required this.postedAt,
  });

  // 从 Map 创建 Product
  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      price: (map['price'] ?? 0).toDouble(),
      location: map['location'] ?? '',
      category: map['category'] ?? '',
      condition: map['condition'] ?? '',
      description: map['description'] ?? '',
      images: List<String>.from(map['images'] ?? []),
      specifications: Map<String, String>.from(map['specifications'] ?? {}),
      seller: Seller.fromMap(map['seller'] ?? {}),
      phoneNumber: map['phoneNumber'] ?? '',
      whatsappNumber: map['whatsappNumber'] ?? '',
      postedAt:
          DateTime.parse(map['postedAt'] ?? DateTime.now().toIso8601String()),
    );
  }

  // 转换为 Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'price': price,
      'location': location,
      'category': category,
      'condition': condition,
      'description': description,
      'images': images,
      'specifications': specifications,
      'seller': seller.toMap(),
      'phoneNumber': phoneNumber,
      'whatsappNumber': whatsappNumber,
      'postedAt': postedAt.toIso8601String(),
    };
  }
}

class Seller {
  final String id;
  final String name;
  final String? avatar;
  final int activeAds;
  final DateTime memberSince;

  Seller({
    required this.id,
    required this.name,
    this.avatar,
    this.activeAds = 0,
    DateTime? memberSince,
  }) : memberSince = memberSince ?? DateTime.now();

  factory Seller.fromMap(Map<String, dynamic> map) {
    return Seller(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      avatar: map['avatar'],
      activeAds: map['activeAds'] ?? 0,
      memberSince: DateTime.parse(
          map['memberSince'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'avatar': avatar,
      'activeAds': activeAds,
      'memberSince': memberSince.toIso8601String(),
    };
  }
}
