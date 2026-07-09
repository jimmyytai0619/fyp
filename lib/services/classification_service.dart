import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/painting.dart' show FileImage;
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:palette_generator/palette_generator.dart';

/// Confidence tier for a classification, per Algorithm 4.7.1 in the FYP report.
///  - high   (>= 0.75): auto-fill category + description
///  - medium (0.50-0.75): show suggested categories for the user to pick
///  - low    (< 0.50): "Unrecognized" -> force manual entry
enum ConfidenceTier { high, medium, low }

/// One category suggestion derived from an ML Kit label (used by the medium tier).
class CategorySuggestion {
  const CategorySuggestion({
    required this.category,
    required this.confidence,
    required this.rawLabel,
  });

  final String category;
  final double confidence;
  final String rawLabel;
}

/// Result of classifying a captured/selected image (Modules 2 & 3).
class ClassificationResult {
  const ClassificationResult({
    required this.tier,
    required this.category,
    required this.confidence,
    required this.rawLabel,
    required this.colorName,
    required this.colorHex,
    required this.material,
    required this.description,
    required this.suggestions,
    required this.possibleBrand,
  });

  final ConfidenceTier tier;

  /// Best-guess category (mapped to a SmartMatch dropdown value).
  final String category;
  final double confidence;
  final String rawLabel;

  // Visual attributes (FR 2.6)
  final String colorName;
  final String colorHex;
  final String? material;

  /// Auto-generated description, e.g. "Black leather wallet" (FR 2.3).
  final String description;

  /// Distinct category suggestions for the medium tier.
  final List<CategorySuggestion> suggestions;

  /// Text read off the item via OCR, surfaced as a possible brand/logo (FR 2.6).
  final String? possibleBrand;

  bool get isHigh => tier == ConfidenceTier.high;
  bool get isMedium => tier == ConfidenceTier.medium;
  bool get isLow => tier == ConfidenceTier.low;

  /// True when the user must confirm/enter the category manually (low tier).
  bool get needsManualReview => tier == ConfidenceTier.low;

  factory ClassificationResult.unrecognized({
    String colorName = 'Unknown',
    String colorHex = '#9E9E9E',
  }) =>
      ClassificationResult(
        tier: ConfidenceTier.low,
        category: 'Other',
        confidence: 0,
        rawLabel: '',
        colorName: colorName,
        colorHex: colorHex,
        material: null,
        description: '',
        suggestions: const [],
        possibleBrand: null,
      );
}

/// Wraps Google ML Kit image labeling, text recognition (OCR), and dominant
/// colour extraction. Runs fully on-device. Call [dispose] when the owning
/// ViewModel is torn down to release the native detectors.
class ClassificationService {
  ClassificationService({
    ImageLabeler? labeler,
    TextRecognizer? textRecognizer,
  })  : _labeler = labeler ??
            ImageLabeler(
              options: ImageLabelerOptions(confidenceThreshold: minConfidence),
            ),
        _textRecognizer = textRecognizer ?? TextRecognizer();

  final ImageLabeler _labeler;
  final TextRecognizer _textRecognizer;

  /// ML Kit won't emit labels below this.
  static const double minConfidence = 0.50;

  /// >= this -> auto-fill (high tier).
  static const double highThreshold = 0.75;

  /// >= this (and < high) -> show suggestions (medium tier). Below -> low tier.
  static const double mediumThreshold = 0.50;

  /// SmartMatch's report-screen categories (must match the View's dropdown).
  static const List<String> categories = [
    'Electronics',
    'IDs & Cards',
    'Bags & Wallets',
    'Keys & Lanyards',
    'Books & Stationery',
    'Clothing & Accessories',
    'Other',
  ];

  Future<ClassificationResult> classify(File imageFile) async {
    final labels = await _labelImage(imageFile);
    final (hex, colorName) = await _dominantColor(imageFile);
    final brand = await _detectBrand(imageFile);

    if (labels.isEmpty) {
      return ClassificationResult.unrecognized(
        colorName: colorName,
        colorHex: hex,
      ).copyWithBrand(brand);
    }

    // NEW HEURISTIC: Instead of just taking the top label (which might be generic
    // like "Plastic" or "Object"), we look for the first label that maps to a
    // specific campus category.
    var top = labels.first;
    var category = _mapToCategory(top.label);

    if (category == 'Other') {
      for (final l in labels) {
        final labelText = l.label.toLowerCase();
        final mapped = _mapToCategory(labelText);
        if (mapped != 'Other') {
          top = l;
          category = mapped;
          break; // Found a specific mapping!
        }
      }
    }

    final tier = _tierFor(top.confidence);
    final material = _inferMaterial(labels);
    final subFeatures = _inferSubFeatures(labels);

    // Build distinct category suggestions (used by the medium tier).
    final seen = <String>{};
    final suggestions = <CategorySuggestion>[];
    for (final l in labels) {
      final cat = _mapToCategory(l.label);
      if (seen.add(cat)) {
        suggestions.add(CategorySuggestion(
          category: cat,
          confidence: l.confidence,
          rawLabel: l.label,
        ));
      }
      if (suggestions.length >= 3) break;
    }

    final description = _buildDescription(
      colorName: colorName,
      material: material,
      noun: _itemNoun(top.label),
      subFeatures: subFeatures,
    );

    return ClassificationResult(
      tier: tier,
      category: category,
      confidence: top.confidence,
      rawLabel: top.label,
      colorName: colorName,
      colorHex: hex,
      material: material,
      description: tier == ConfidenceTier.low ? '' : description,
      suggestions: suggestions,
      possibleBrand: brand,
    );
  }

  ConfidenceTier _tierFor(double c) {
    if (c >= highThreshold) return ConfidenceTier.high;
    if (c >= mediumThreshold) return ConfidenceTier.medium;
    return ConfidenceTier.low;
  }

  Future<List<ImageLabel>> _labelImage(File file) async {
    final labels = await _labeler.processImage(InputImage.fromFile(file));
    labels.sort((a, b) => b.confidence.compareTo(a.confidence));
    return labels;
  }

  /// OCR: returns the most plausible brand/logo token found on the item, or null.
  Future<String?> _detectBrand(File file) async {
    try {
      final recognized =
          await _textRecognizer.processImage(InputImage.fromFile(file));
      String? best;
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          final t = line.text.trim();
          // Heuristic: short, mostly-alphabetic tokens read like brand names.
          final letters = t.replaceAll(RegExp(r'[^A-Za-z]'), '');
          if (t.length >= 2 &&
              t.length <= 15 &&
              letters.length >= t.length * 0.6) {
            if (best == null || t.length > best.length) best = t;
          }
        }
      }
      return best;
    } catch (_) {
      return null; // OCR is best-effort
    }
  }

  /// Folds a fine-grained ML Kit label into one of SmartMatch's standardized categories.
  String _mapToCategory(String mlLabel) {
    final label = mlLabel.toLowerCase();

    const electronics = [
      'phone', 'mobile', 'laptop', 'computer', 'tablet', 'headphone',
      'earphone', 'charger', 'camera', 'watch', 'mouse', 'keyboard',
      'cable', 'television', 'speaker', 'power bank', 'kindle', 'gadget',
      'microphone', 'monitor', 'usb', 'pendrive', 'electronic',
    ];

    const idsAndCards = [
      'card', 'id', 'identity', 'passport', 'license', 'document', 'paper',
      'ticket', 'badge', 'credit card', 'debit card', 'bank card', 'membership',
      'smartcard', 'student id',
    ];

    const bagsAndWallets = [
      'bag', 'backpack', 'wallet', 'purse', 'handbag', 'luggage', 'pouch',
      'satchel', 'briefcase', 'suitcase', 'tote', 'knapsack', 'clutch',
    ];

    const keysAndLanyards = [
      'key', 'lanyard', 'keychain', 'car key', 'house key', 'fob',
    ];

    const booksAndStationery = [
      'book', 'notebook', 'textbook', 'calculator', 'pen', 'pencil', 'stationery',
      'folder', 'binder', 'ruler', 'eraser', 'pencil case', 'journal', 'clipboard',
    ];

    const clothingAndAccessories = [
      'umbrella', 'glasses', 'sunglasses', 'jewelry', 'ring',
      'necklace', 'bracelet', 'hat', 'cap', 'scarf', 'glove', 'water bottle',
      'bottle', 'tumbler', 'flask', 'clothing', 'shirt', 'jacket', 'coat',
      'shoe', 'sneaker', 'sandal', 'socks', 'belt',
    ];

    bool hit(List<String> keys) => keys.any(label.contains);

    if (hit(electronics)) return 'Electronics';
    if (hit(idsAndCards)) return 'IDs & Cards';
    if (hit(bagsAndWallets)) return 'Bags & Wallets';
    if (hit(keysAndLanyards)) return 'Keys & Lanyards';
    if (hit(booksAndStationery)) return 'Books & Stationery';
    if (hit(clothingAndAccessories)) return 'Clothing & Accessories';

    return 'Other';
  }

  /// Lowercased object noun for the description (e.g. "Wallet" -> "wallet").
  String _itemNoun(String mlLabel) => mlLabel.trim().toLowerCase();

  /// Looks for a material keyword among the returned labels (best-effort).
  String? _inferMaterial(List<ImageLabel> labels) {
    const materials = [
      'leather', 'metal', 'plastic', 'fabric', 'denim', 'wood', 'cotton',
      'rubber', 'glass', 'paper', 'wool', 'silk', 'polyester', 'nylon',
      'canvas', 'ceramic',
    ];
    for (final l in labels) {
      final t = l.label.toLowerCase();
      for (final m in materials) {
        if (t.contains(m)) return m;
      }
    }
    return null;
  }

  /// Detects secondary attributes like zippers, straps, or patterns.
  List<String> _inferSubFeatures(List<ImageLabel> labels) {
    const subFeatures = {
      'zipper': ['zipper', 'zip'],
      'strap': ['strap', 'handle'],
      'pattern': ['pattern', 'print', 'floral', 'stripe', 'checkered'],
      'screen': ['screen', 'display'],
      'case': ['case', 'cover'],
      'logo': ['logo', 'branding'],
    };
    final detected = <String>{};
    for (final l in labels) {
      final t = l.label.toLowerCase();
      for (final entry in subFeatures.entries) {
        if (entry.value.any((v) => t.contains(v))) {
          detected.add(entry.key);
        }
      }
    }
    return detected.toList();
  }

  /// FR 2.3 — "Black leather wallet with zipper" style description.
  String _buildDescription({
    required String colorName,
    String? material,
    required String noun,
    List<String>? subFeatures,
  }) {
    final parts = <String>[];
    if (colorName != 'Unknown') parts.add(colorName);
    if (material != null) parts.add(material);
    parts.add(noun);

    var s = parts.join(' ');
    if (s.isNotEmpty) {
      s = '${s[0].toUpperCase()}${s.substring(1)}';
    }

    if (subFeatures != null && subFeatures.isNotEmpty) {
      final featureList = subFeatures.join(', ');
      s = s.isEmpty ? 'With $featureList' : '$s with $featureList';
    }

    return s;
  }

  Future<(String, String)> _dominantColor(File file) async {
    final palette = await PaletteGenerator.fromImageProvider(
      FileImage(file),
      maximumColorCount: 12,
    );

    final color = _pickRepresentativeColor(palette);
    if (color == null) return ('#9E9E9E', 'Unknown');

    final hex =
        '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    return (hex, _colorName(color.r, color.g, color.b));
  }

  /// Chooses the colour that best represents the *object* rather than the
  /// background. The plain dominant colour is often a dark surface/shadow, so
  /// we score each swatch by how common AND how saturated it is — a clearly
  /// coloured swatch with decent area beats a slightly larger grey/black one.
  dynamic _pickRepresentativeColor(PaletteGenerator palette) {
    final swatches = palette.paletteColors;
    if (swatches.isEmpty) {
      return palette.dominantColor?.color ??
          (palette.colors.isEmpty ? null : palette.colors.first);
    }

    double bestScore = -1;
    var best = swatches.first.color;
    for (final sw in swatches) {
      final c = sw.color;
      final hsv = _toHsv(c.r, c.g, c.b);
      final s = hsv.$2;
      final v = hsv.$3;

      // population (area) weighted
      // boost by saturation (so a coloured swatch beats a neutral one)
      // penalize very dark colors (v < 0.2) to avoid shadows/background being picked as "Black"
      double score = sw.population * (0.35 + 0.65 * s);
      if (v < 0.2) score *= 0.1; 

      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best;
  }

  /// RGB (0..1) -> HSV. Returns (hue 0..360, saturation 0..1, value 0..1).
  (double, double, double) _toHsv(double r, double g, double b) {
    final max = [r, g, b].reduce((a, b) => a > b ? a : b);
    final min = [r, g, b].reduce((a, b) => a < b ? a : b);
    final delta = max - min;

    double h;
    if (delta == 0) {
      h = 0;
    } else if (max == r) {
      h = 60 * (((g - b) / delta) % 6);
    } else if (max == g) {
      h = 60 * (((b - r) / delta) + 2);
    } else {
      h = 60 * (((r - g) / delta) + 4);
    }
    if (h < 0) h += 360;

    final s = max == 0 ? 0.0 : delta / max;
    return (h, s, max);
  }

  /// Names a colour by finding the nearest entry in a broad colour vocabulary
  /// using perceptual CIELAB distance (Delta-E). This supports *any* colour:
  /// the exact value is always kept as [ClassificationResult.colorHex], and this
  /// returns the closest human-readable name (e.g. Maroon, Navy, Olive, Teal,
  /// Beige…), not a handful of buckets.
  String _colorName(double r, double g, double b) {
    final target = _rgbToLab(r, g, b);
    String bestName = 'Unknown';
    double bestDist = double.infinity;
    for (final entry in _namedColors.entries) {
      final rgb = entry.value;
      final lab = _rgbToLab(
        ((rgb >> 16) & 0xFF) / 255.0,
        ((rgb >> 8) & 0xFF) / 255.0,
        (rgb & 0xFF) / 255.0,
      );
      final dl = target.$1 - lab.$1;
      final da = target.$2 - lab.$2;
      final db = target.$3 - lab.$3;
      final dist = dl * dl + da * da + db * db;
      if (dist < bestDist) {
        bestDist = dist;
        bestName = entry.key;
      }
    }
    return bestName;
  }

  /// sRGB (0..1) -> CIELAB (L, a, b), D65 white point.
  (double, double, double) _rgbToLab(double r, double g, double b) {
    double lin(double c) =>
        c <= 0.04045 ? c / 12.92 : _pow((c + 0.055) / 1.055, 2.4);
    final rl = lin(r), gl = lin(g), bl = lin(b);

    // Linear RGB -> XYZ (D65)
    final x = (rl * 0.4124 + gl * 0.3576 + bl * 0.1805) / 0.95047;
    final y = (rl * 0.2126 + gl * 0.7152 + bl * 0.0722) / 1.00000;
    final z = (rl * 0.0193 + gl * 0.1192 + bl * 0.9505) / 1.08883;

    double f(double t) =>
        t > 0.008856 ? _pow(t, 1 / 3) : (7.787 * t + 16 / 116);
    final fx = f(x), fy = f(y), fz = f(z);

    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
  }

  double _pow(double base, double exp) => math.pow(base, exp).toDouble();

  /// A broad named-colour vocabulary (name -> 0xRRGGBB). Extend freely — the
  /// nearest-match handles everything in between.
  static const Map<String, int> _namedColors = {
    'Black': 0x000000,
    'White': 0xFFFFFF,
    'Grey': 0x808080,
    'Silver': 0xC0C0C0,
    'Charcoal': 0x36454F,
    'Red': 0xE32636,
    'Crimson': 0xDC143C,
    'Maroon': 0x800000,
    'Pink': 0xFFC0CB,
    'Salmon': 0xFA8072,
    'Orange': 0xFF8C00,
    'Brown': 0x8B5A2B,
    'Tan': 0xD2B48C,
    'Beige': 0xE8D9B5,
    'Gold': 0xD4AF37,
    'Yellow': 0xFFD700,
    'Olive': 0x808000,
    'Lime': 0xBFFF00,
    'Green': 0x2E8B22,
    'Teal': 0x008080,
    'Cyan': 0x00CED1,
    'Turquoise': 0x40E0D0,
    'Navy': 0x1F3A93,
    'Blue': 0x2563EB,
    'SkyBlue': 0x87CEEB,
    'Indigo': 0x4B0082,
    'Purple': 0x800080,
    'Violet': 0x8A2BE2,
    'Magenta': 0xC71585,
  };

  Future<void> dispose() async {
    await _labeler.close();
    await _textRecognizer.close();
  }
}

extension on ClassificationResult {
  ClassificationResult copyWithBrand(String? brand) => ClassificationResult(
        tier: tier,
        category: category,
        confidence: confidence,
        rawLabel: rawLabel,
        colorName: colorName,
        colorHex: colorHex,
        material: material,
        description: description,
        suggestions: suggestions,
        possibleBrand: brand,
      );
}
