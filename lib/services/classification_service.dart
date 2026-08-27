import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

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

  bool get isHigh => tier == ConfidenceTier.high;
  bool get isMedium => tier == ConfidenceTier.medium;
  bool get isLow => tier == ConfidenceTier.low;

  /// True when the user must confirm/enter the category manually (low tier).
  bool get needsManualReview => tier == ConfidenceTier.low;

  factory ClassificationResult.unrecognized({
    String colorName = 'Unknown',
    String colorHex = '#9E9E9E',
  }) => ClassificationResult(
    tier: ConfidenceTier.low,
    category: 'Other',
    confidence: 0,
    rawLabel: '',
    colorName: colorName,
    colorHex: colorHex,
    material: null,
    description: '',
    suggestions: const [],
  );
}

/// Wraps Google ML Kit image labeling and dominant colour extraction. Runs
/// fully on-device. Call [dispose] when the owning ViewModel is torn down to
/// release the native detector.
class ClassificationService {
  ClassificationService({ImageLabeler? labeler})
    : _labeler =
          labeler ??
          ImageLabeler(
            options: ImageLabelerOptions(confidenceThreshold: labelThreshold),
          );

  final ImageLabeler _labeler;

  /// Low bar so more candidate labels are returned for category mapping — the
  /// final tier is still gated by the high/medium thresholds below, so this
  /// improves the category hit-rate without auto-filling low-confidence guesses.
  static const double labelThreshold = 0.30;

  /// (kept for compatibility) medium-tier floor.
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
    'Water Bottles',
    'Other',
  ];

  Future<ClassificationResult> classify(File imageFile) async {
    final labels = await _labelImage(imageFile);
    if (kDebugMode) {
      debugPrint(
        '[ClassificationService] labels: ${labels.take(10).map((l) => '${l.label} ${(l.confidence * 100).toStringAsFixed(0)}%').join(', ')}',
      );
    }
    var hex = '#9E9E9E';
    var colorName = 'Unknown';
    try {
      final color = await _dominantColor(imageFile);
      hex = color.$1;
      colorName = color.$2;
    } catch (_) {
      // Colour is a helpful attribute, but it must never cancel a successful
      // category classification for an unusual image size/orientation.
    }
    if (labels.isEmpty) {
      return ClassificationResult.unrecognized(
        colorName: colorName,
        colorHex: hex,
      );
    }

    // NEW HEURISTIC: Instead of just taking the top label (which might be generic
    // like "Plastic" or "Object"), we look for the first label that maps to a
    // specific campus category.
    var top = labels.first;
    var category = mapLabelToCategory(top.label);

    if (category == 'Other') {
      for (final l in labels) {
        final labelText = l.label.toLowerCase();
        final mapped = mapLabelToCategory(labelText);
        if (mapped != 'Other') {
          top = l;
          category = mapped;
          break; // Found a specific mapping!
        }
      }
    }

    // A generic label such as "object" can be highly confident without giving
    // us a trustworthy SmartMatch category. Never auto-fill "Other" solely
    // because ML Kit was confident about that generic source label.
    final tier = category == 'Other'
        ? ConfidenceTier.low
        : _tierFor(top.confidence);
    final material = _inferMaterial(labels);
    final subFeatures = _inferSubFeatures(labels);

    // Build distinct category suggestions (used by the medium tier).
    final seen = <String>{};
    final suggestions = <CategorySuggestion>[];
    for (final l in labels) {
      if (l.confidence < mediumThreshold) continue;
      final cat = mapLabelToCategory(l.label);
      if (cat != 'Other' && seen.add(cat)) {
        suggestions.add(
          CategorySuggestion(
            category: cat,
            confidence: l.confidence,
            rawLabel: l.label,
          ),
        );
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

  /// Folds a fine-grained ML Kit label into one of SmartMatch's standardized categories.
  static String mapLabelToCategory(String mlLabel) {
    final label = mlLabel
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();

    const electronics = [
      'phone',
      'mobile',
      'smartphone',
      'iphone',
      'android',
      'laptop',
      'computer',
      'tablet',
      'ipad',
      'headphone',
      'earphone',
      'earbud',
      'airpod',
      'charger',
      'adapter',
      'camera',
      'watch',
      'smartwatch',
      'mouse',
      'keyboard',
      'cable',
      'cord',
      'television',
      'speaker',
      'power bank',
      'powerbank',
      'kindle',
      'gadget',
      'microphone',
      'monitor',
      'usb',
      'pendrive',
      'flash drive',
      'electronic',
      'remote',
      'controller',
      'console',
      'router',
      'drone',
    ];

    const idsAndCards = [
      'card',
      'id',
      'identity',
      'passport',
      'license',
      'ticket',
      'badge',
      'credit card',
      'debit card',
      'bank card',
      'membership',
      'smartcard',
      'student id',
    ];

    const bagsAndWallets = [
      'bag',
      'backpack',
      'wallet',
      'purse',
      'handbag',
      'luggage',
      'pouch',
      'satchel',
      'briefcase',
      'suitcase',
      'tote',
      'knapsack',
      'clutch',
    ];

    const keysAndLanyards = [
      'key',
      'lanyard',
      'keychain',
      'car key',
      'house key',
      'fob',
    ];

    const booksAndStationery = [
      'book',
      'notebook',
      'textbook',
      'calculator',
      'pen',
      'pencil',
      'stationery',
      'folder',
      'binder',
      'ruler',
      'eraser',
      'pencil case',
      'journal',
      'clipboard',
      'paper',
      'document',
    ];

    const clothingAndAccessories = [
      'umbrella',
      'glasses',
      'sunglasses',
      'jewelry',
      'ring',
      'necklace',
      'bracelet',
      'hat',
      'scarf',
      'glove',
      'clothing',
      'shirt',
      'jacket',
      'coat',
      'shoe',
      'sneaker',
      'sandal',
      'socks',
      'belt',
    ];

    const waterBottles = [
      'water bottle',
      'bottle',
      'tumbler',
      'flask',
      'mug',
      'cup',
      'thermos',
      'drinkware',
      'tableware',
      'kitchenware',
    ];

    // Match complete words/phrases only. Substring matching made labels such as
    // "video", "solid", "cardboard", and "capsule" hit id/card/cap.
    bool hit(List<String> keys) => keys.any((key) {
      final normalizedKey = key
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
          .trim();
      return RegExp(
        '(^| )${RegExp.escape(normalizedKey)}( |\$)',
      ).hasMatch(label);
    });

    if (hit(electronics)) return 'Electronics';
    if (hit(idsAndCards)) return 'IDs & Cards';
    if (hit(waterBottles)) return 'Water Bottles'; // Move up!
    if (hit(bagsAndWallets)) return 'Bags & Wallets';
    if (hit(keysAndLanyards)) return 'Keys & Lanyards';
    if (hit(booksAndStationery)) return 'Books & Stationery';

    // Handle "cap" specially to avoid "Bottle cap" -> "Clothing"
    if (hit(const ['cap']) && !hit(const ['bottle'])) {
      return 'Clothing & Accessories';
    }

    if (hit(clothingAndAccessories)) return 'Clothing & Accessories';

    return 'Other';
  }

  /// Lowercased object noun for the description (e.g. "Wallet" -> "wallet").
  String _itemNoun(String mlLabel) => mlLabel.trim().toLowerCase();

  /// Looks for a material keyword among the returned labels (best-effort).
  String? _inferMaterial(List<ImageLabel> labels) {
    const materials = [
      'leather',
      'metal',
      'plastic',
      'fabric',
      'denim',
      'wood',
      'cotton',
      'rubber',
      'glass',
      'paper',
      'wool',
      'silk',
      'polyester',
      'nylon',
      'canvas',
      'ceramic',
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
    // A small, fixed-size decode is sufficient for colour analysis and avoids
    // processing millions of camera pixels on the UI isolate.
    final codec = await ui.instantiateImageCodec(
      await file.readAsBytes(),
      targetWidth: 160,
      targetHeight: 160,
      allowUpscaling: false,
    );
    final frame = await codec.getNextFrame();
    final decoded = frame.image;
    final byteData = await decoded.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final width = decoded.width;
    final height = decoded.height;
    decoded.dispose();
    codec.dispose();

    if (byteData == null) return ('#9E9E9E', 'Unknown');
    final color = extractCenterObjectColor(
      byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      ),
      width,
      height,
    );
    if (color == null) return ('#9E9E9E', 'Unknown');

    final hex =
        '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    final name = _colorName(color.r, color.g, color.b);
    if (kDebugMode) {
      debugPrint('[ClassificationService] center-object color: $name $hex');
    }
    return (hex, name);
  }

  /// Extracts the main colour of an item expected near the middle of a photo.
  ///
  /// Pixels inside a central ellipse receive progressively more weight toward
  /// the exact centre. Colours that also dominate the outer image border are
  /// penalised because they are likely to be the table, floor, or wall behind
  /// the item. Unlike the old palette heuristic, this does not favour saturated
  /// colours, so neutral objects such as black phones and white cards are not
  /// displaced by a small colourful background patch.
  @visibleForTesting
  static ui.Color? extractCenterObjectColor(
    Uint8List rgba,
    int width,
    int height,
  ) {
    if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
      return null;
    }

    final centreBuckets = <int, _WeightedColorBucket>{};
    final borderWeights = <int, double>{};
    final centreX = width / 2;
    final centreY = height / 2;
    final radiusX = math.max(1.0, width * 0.28);
    final radiusY = math.max(1.0, height * 0.32);
    final borderX = math.max(1, (width * 0.14).round());
    final borderY = math.max(1, (height * 0.14).round());

    int bucketKey(int r, int g, int b) =>
        ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final offset = (y * width + x) * 4;
        final alpha = rgba[offset + 3];
        if (alpha < 32) continue;

        final r = rgba[offset];
        final g = rgba[offset + 1];
        final b = rgba[offset + 2];
        final key = bucketKey(r, g, b);

        if (x < borderX ||
            x >= width - borderX ||
            y < borderY ||
            y >= height - borderY) {
          borderWeights[key] = (borderWeights[key] ?? 0) + 1;
        }

        final dx = (x + 0.5 - centreX) / radiusX;
        final dy = (y + 0.5 - centreY) / radiusY;
        final distanceSquared = dx * dx + dy * dy;
        if (distanceSquared > 1) continue;

        // The exact middle is up to 7x more important than the edge of the ROI.
        final closeness = 1 - distanceSquared;
        final weight = 1 + 6 * closeness * closeness;
        final bucket = centreBuckets.putIfAbsent(key, _WeightedColorBucket.new);
        bucket.add(r, g, b, weight);
      }
    }

    if (centreBuckets.isEmpty) return null;
    final strongestBorder = borderWeights.values.fold<double>(
      0,
      (best, value) => value > best ? value : best,
    );

    _WeightedColorBucket? best;
    var bestScore = -1.0;
    for (final entry in centreBuckets.entries) {
      final backgroundShare = strongestBorder == 0
          ? 0.0
          : (borderWeights[entry.key] ?? 0) / strongestBorder;
      final score = entry.value.weight * (1 - 0.80 * backgroundShare);
      if (score > bestScore) {
        bestScore = score;
        best = entry.value;
      }
    }

    if (best == null || best.weight == 0) return null;
    return ui.Color.fromARGB(
      255,
      (best.red / best.weight).round().clamp(0, 255),
      (best.green / best.weight).round().clamp(0, 255),
      (best.blue / best.weight).round().clamp(0, 255),
    );
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
  }
}

class _WeightedColorBucket {
  double weight = 0;
  double red = 0;
  double green = 0;
  double blue = 0;

  void add(int r, int g, int b, double pixelWeight) {
    weight += pixelWeight;
    red += r * pixelWeight;
    green += g * pixelWeight;
    blue += b * pixelWeight;
  }
}
