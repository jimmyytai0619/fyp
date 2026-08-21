class ItemReport {
  final String id;
  final String imageUrl;
  final String category;
  final String locationFound;
  final String description;
  final String status;
  final DateTime createdAt;

  /// A lost report the owner (or a completed return) has closed.
  final bool isResolved;

  /// A found item that has been handed back.
  final bool isReturned;

  const ItemReport({
    required this.id,
    required this.imageUrl,
    required this.category,
    required this.locationFound,
    required this.description,
    required this.status,
    required this.createdAt,
    this.isResolved = false,
    this.isReturned = false,
  });

  /// Closed either way — no longer active for matching.
  bool get isClosed => isResolved || isReturned;

  factory ItemReport.fromMap(Map<String, dynamic> map) {
    return ItemReport(
      id: map['id'] as String? ?? '',
      imageUrl: map['image_url'] as String? ?? '',
      category: map['category'] as String? ?? 'Unknown',
      locationFound: map['location_found'] as String? ?? '',
      description: map['description'] as String? ?? '',
      status: map['status'] as String? ?? 'Pending',
      isResolved: map['is_resolved'] as bool? ?? false,
      isReturned: map['is_returned'] as bool? ?? false,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
