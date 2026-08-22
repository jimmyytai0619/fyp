class AppNotification {
  final String id;
  final String title;
  final String message;
  final bool isRead;
  final DateTime createdAt;

  /// The found item this alert points to (null for non-match notifications).
  final String? itemId;

  /// Distinguishes alert kinds, e.g. 'claim_request' (someone claimed your
  /// found item) vs. a match alert (null / other). Drives where a tap goes.
  final String? type;

  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.itemId,
    this.type,
  });

  /// True when this alert is a finder's "someone wants to claim your item"
  /// notification, which should open the Claims → Requests tab.
  bool get isClaimRequest => type == 'claim_request';

  /// True when this alert tells the claimant the finder approved/rejected their
  /// claim, which should open the Claims → My Claims tab.
  bool get isClaimDecision => type == 'claim_decision';

  /// True when this alert confirms the handover is complete (item returned),
  /// which should also open the Claims → My Claims tab.
  bool get isClaimReturned => type == 'claim_returned';

  /// True when this alert is a new handover chat message, which should open the
  /// Claims → My Claims tab so the user can reply.
  bool get isChatMessage => type == 'chat_message';

  /// True when the claimant verified the handover code — sent to the finder,
  /// so it opens the Claims → Requests tab.
  bool get isHandoverVerified => type == 'handover_verified';

  /// Two-party return: claimant is asked to confirm receipt (→ My Claims).
  bool get isReturnPending => type == 'return_pending';

  /// Two-party return: finder is told the claimant confirmed / denied receipt
  /// (→ Requests).
  bool get isReturnDecision =>
      type == 'return_confirmed' || type == 'return_disputed';

  /// Any claim-related alert that should open the Claims screen.
  bool get isClaimRelated =>
      isClaimRequest ||
      isClaimDecision ||
      isClaimReturned ||
      isChatMessage ||
      isHandoverVerified ||
      isReturnPending ||
      isReturnDecision;

  /// Alerts aimed at the finder open the Requests tab; the rest open My Claims.
  bool get opensFinderTab => isClaimRequest || isHandoverVerified || isReturnDecision;

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      title: title,
      message: message,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      itemId: itemId,
      type: type,
    );
  }

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      message: map['message'] as String? ?? '',
      isRead: map['is_read'] as bool? ?? false,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      itemId: map['item_id'] as String?,
      type: map['type'] as String?,
    );
  }
}
