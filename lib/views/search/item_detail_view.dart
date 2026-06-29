import 'package:flutter/material.dart';

import '../../models/match_result.dart';
import '../../services/api_service.dart';
import '../claims/claim_quiz_view.dart';

class ItemDetailView extends StatelessWidget {
  final MatchResult item;

  const ItemDetailView({super.key, required this.item});

  static const _primaryBlue = Color(0xFF1565C0);

  Future<void> _startClaim(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    String? question;
    try {
      question = await ApiService().getSecurityQuestion(item.id);
    } catch (_) {
      question = null;
    }

    if (!context.mounted) return;
    Navigator.of(context).pop(); // close loading dialog

    if (question == null || question.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'This item has no ownership question set, so it can\'t be claimed in-app.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      );
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClaimQuizView(itemId: item.id, question: question!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final score = item.confidenceScore;
    final badgeColor = score >= 90
        ? const Color(0xFF2E7D32)
        : score >= 70
            ? const Color(0xFFF57F17)
            : const Color(0xFFC62828);

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        title: const Text('Item Details',
            style: TextStyle(fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hero image
            if (item.imageUrl.isNotEmpty)
              Hero(
                tag: 'item_${item.id}',
                child: Image.network(
                  item.imageUrl,
                  height: 260,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 260,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.broken_image_outlined,
                        size: 60, color: Colors.grey),
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Confidence badge
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome,
                                color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '${score.toStringAsFixed(1)}% Match',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  _detailCard(children: [
                    _row(Icons.category_outlined, 'Category', item.category),
                    const Divider(height: 24),
                    _row(Icons.location_on_outlined, 'Found At',
                        item.locationFound),
                    if (item.description.isNotEmpty) ...[
                      const Divider(height: 24),
                      _row(Icons.notes_rounded, 'Description',
                          item.description),
                    ],
                    if (item.tags.isNotEmpty) ...[
                      const Divider(height: 24),
                      _tagRow(item.tags),
                    ],
                    const Divider(height: 24),
                    _row(Icons.calendar_today_outlined, 'Reported On',
                        _formatDate(item.createdAt)),
                  ]),

                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.shield_outlined),
                      label: const Text('Claim This Item',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => _startClaim(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailCard({required List<Widget> children}) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );

  Widget _row(IconData icon, String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: _primaryBlue),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9E9E9E),
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A237E))),
            ],
          ),
        ],
      );

  Widget _tagRow(List<String> tags) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.label_outline_rounded,
              size: 18, color: _primaryBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: tags
                  .map((t) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F2FD),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(t,
                            style: const TextStyle(
                                fontSize: 12,
                                color: _primaryBlue,
                                fontWeight: FontWeight.w600)),
                      ))
                  .toList(),
            ),
          ),
        ],
      );

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';
}
