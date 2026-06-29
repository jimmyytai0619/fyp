class ClaimMessage {
  final String id;
  final String claimId;
  final String senderId;
  final String body;
  final DateTime createdAt;

  const ClaimMessage({
    required this.id,
    required this.claimId,
    required this.senderId,
    required this.body,
    required this.createdAt,
  });

  factory ClaimMessage.fromMap(Map<String, dynamic> map) {
    return ClaimMessage(
      id: map['id'] as String? ?? '',
      claimId: map['claim_id'] as String? ?? '',
      senderId: map['sender_id'] as String? ?? '',
      body: map['body'] as String? ?? '',
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
