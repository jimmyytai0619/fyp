import 'dart:io';

import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

/// Confidence tiers for the three-tier handling in the report UI (4.7.1).
enum ConfidenceTier { high, medium, low }

/// One candidate category with its confidence (0.0–1.0).
class CategorySuggestion {
  final String category;
  final double confidence;

  const CategorySuggestion(this.category, this.confidence);
}

/// Result of on-device image classification.
class ClassificationResult {
  final String category; // one of ClassificationService.categories, or 'Unrecognized'
  final double confidence; // 0.0–1.0 for the chosen category
  final String description; // auto-generated from top labels
  final String colorName; // 'Unknown' when not detected
  final String colorHex; // hex string, used only when colorName != 'Unknown'
  final String? possibleBrand;
  final String? material;
  final List<CategorySuggestion> suggestions;

  const ClassificationResult({
    required this.category,
    required this.confidence,
    required this.description,
    this.colorName = 'Unknown',
    this.colorHex = '#9E9E9E',
    this.possibleBrand,
    this.material,
    this.suggestions = const [],
  });

  ConfidenceTier get tier {
    if (confidence >= 0.75) return ConfidenceTier.high;
    if (confidence >= 0.50) return ConfidenceTier.medium;
    return ConfidenceTier.low;
  }

  bool get isHigh => tier == ConfidenceTier.high;
  bool get isMedium => tier == ConfidenceTier.medium;
  bool get needsManualReview => tier == ConfidenceTier.low;
}

/// Runs Google ML Kit image labelling on-device and maps the generic labels
/// onto the app's item categories.
class ClassificationService {
  final ImageLabeler _labeler =
      ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.4));

  /// The item categories used across the app's report/browse flows.
  static const List<String> categories = [
    'Electronics',
    'IDs & Cards',
    'Bags & Wallets',
    'Other',
  ];

  /// Keyword → category map. ML Kit returns generic English labels; we match
  /// them (case-insensitive, substring) to the app's categories.
  static const Map<String, List<String>> _keywords = {
    'Electronics': [
      'phone', 'mobile', 'laptop', 'computer', 'tablet', 'camera', 'headphone',
      'earphone', 'earbud', 'watch', 'charger', 'cable', 'keyboard', 'mouse',
      'television', 'screen', 'monitor', 'speaker', 'electronic', 'gadget',
      'fan', 'remote', 'console', 'device', 'battery', 'power bank',
    ],
    'Bags & Wallets': [
      'bag', 'wallet', 'purse', 'backpack', 'handbag', 'luggage', 'suitcase',
      'pouch', 'satchel', 'briefcase',
    ],
    'IDs & Cards': [
      'card', 'id', 'identity', 'licence', 'license', 'passport', 'document',
      'paper', 'ticket', 'badge',
    ],
  };

  Future<ClassificationResult> classify(File file) async {
    final input = InputImage.fromFilePath(file.path);
    final labels = await _labeler.processImage(input);

    if (labels.isEmpty) {
      return const ClassificationResult(
        category: 'Unrecognized',
        confidence: 0.0,
        description: '',
      );
    }

    labels.sort((a, b) => b.confidence.compareTo(a.confidence));

    // Accumulate a score per category from any matching labels.
    final scores = <String, double>{};
    for (final label in labels) {
      final text = label.label.toLowerCase();
      for (final entry in _keywords.entries) {
        if (entry.value.any((kw) => text.contains(kw))) {
          scores[entry.key] =
              (scores[entry.key] ?? 0) + label.confidence;
        }
      }
    }

    // Build the description from the two strongest labels.
    final description = labels
        .take(2)
        .map((l) => l.label)
        .join(', ');

    if (scores.isEmpty) {
      // Recognised something, but nothing that maps to our categories.
      return ClassificationResult(
        category: 'Other',
        confidence: labels.first.confidence.clamp(0.0, 1.0),
        description: description,
      );
    }

    // Rank categories by accumulated score (clamped to a 0–1 confidence).
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final suggestions = ranked
        .map((e) => CategorySuggestion(e.key, e.value.clamp(0.0, 1.0)))
        .toList();

    final best = ranked.first;
    return ClassificationResult(
      category: best.key,
      confidence: best.value.clamp(0.0, 1.0),
      description: description,
      suggestions: suggestions,
    );
  }

  void dispose() => _labeler.close();
}
