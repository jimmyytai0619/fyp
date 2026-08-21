/// Predefined CCTV-monitored campus handover locations (FR 5.6).
const List<String> kSafeZones = [
  'Security Office (Main Guard Post)',
  'Library Help Desk',
  'Student Affairs Office (Block A)',
  'FICT Faculty Admin Counter',
];

class Claim {
  final String id;
  final String foundItemId;
  final String claimantId;
  final String finderId;
  final String status; // Quiz, Pending, Verified, Rejected, Returned
  final int quizAttempts;
  final bool isLocked;
  final String? safeZone;
  final DateTime createdAt;

  /// Handover proof photo the finder uploaded when marking the item returned.
  final String? returnEvidenceUrl;

  // Joined found-item details (for display)
  final String itemCategory;
  final String itemImageUrl;
  final String itemLocation;

  const Claim({
    required this.id,
    required this.foundItemId,
    required this.claimantId,
    required this.finderId,
    required this.status,
    required this.quizAttempts,
    required this.isLocked,
    required this.safeZone,
    required this.createdAt,
    required this.itemCategory,
    required this.itemImageUrl,
    required this.itemLocation,
    this.returnEvidenceUrl,
  });

  factory Claim.fromMap(Map<String, dynamic> map) {
    final item = map['found_items'] is Map
        ? Map<String, dynamic>.from(map['found_items'] as Map)
        : <String, dynamic>{};
    return Claim(
      id: map['id'] as String,
      foundItemId: map['found_item_id'] as String? ?? '',
      claimantId: map['claimant_id'] as String? ?? '',
      finderId: map['finder_id'] as String? ?? '',
      status: map['status'] as String? ?? 'Pending',
      quizAttempts: (map['quiz_attempts'] as num?)?.toInt() ?? 0,
      isLocked: map['is_locked'] as bool? ?? false,
      safeZone: map['safe_zone'] as String?,
      returnEvidenceUrl: map['return_evidence_url'] as String?,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      itemCategory: item['category'] as String? ?? 'Item',
      itemImageUrl: item['image_url'] as String? ?? '',
      itemLocation: item['location_found'] as String? ?? '',
    );
  }
}
