import 'dart:convert';

class MatchResult {
  final String id;
  final String imageUrl;
  final String category;
  final String locationFound;
  final String description;
  final List<String> tags;
  final double confidenceScore;
  final DateTime createdAt;

  const MatchResult({
    required this.id,
    required this.imageUrl,
    required this.category,
    required this.locationFound,
    required this.description,
    required this.tags,
    required this.confidenceScore,
    required this.createdAt,
  });

  static List<String> _parseTags(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return List<String>.from(raw);
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return List<String>.from(decoded);
      } catch (_) {}
    }
    return [];
  }

  factory MatchResult.fromMap(Map<String, dynamic> map) {
    return MatchResult(
      id: map['id'] as String,
      imageUrl: map['image_url'] as String? ?? '',
      category: map['category'] as String? ?? 'Unknown',
      locationFound: map['location_found'] as String? ?? '',
      description: map['description'] as String? ?? '',
      tags: _parseTags(map['tags']),
      confidenceScore: (map['confidence_score'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
