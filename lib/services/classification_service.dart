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
    final passes = await _labelImagePasses(imageFile);
    final labels = _mergeLabels(passes.full, passes.object);
    if (kDebugMode) {
      debugPrint(
        '[ClassificationService] full labels: ${_formatLabels(passes.full)}',
      );
      debugPrint(
        '[ClassificationService] center-object labels: '
        '${_formatLabels(passes.object)}',
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

    // The report flow asks users to keep the item in the middle of the photo.
    // Prefer a category found in that crop, where a face/room/background is much
    // less likely to outrank a small item such as a key.
    var top = _firstMappedLabel(passes.object) ?? labels.first;
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

    // ML Kit's base model sometimes describes a close-up key by its parts
    // instead of returning "Key": a narrow shaft as "Nail", the bow/hole as
    // "Goggles", and the reflective body as "Tableware". Require all three
    // independent shape cues before suggesting Keys & Lanyards.
    final keyShapeScore = keyShapeEvidenceScore({
      for (final label in passes.object)
        label.label.toLowerCase(): label.confidence,
    });
    var effectiveConfidence = top.confidence;
    var effectiveRawLabel = top.label;
    var effectiveNoun = _itemNoun(top.label);
    if (keyShapeScore != null && category != 'Keys & Lanyards') {
      category = 'Keys & Lanyards';
      effectiveConfidence = keyShapeScore;
      effectiveRawLabel = 'key-shape evidence';
      effectiveNoun = 'key';
      if (kDebugMode) {
        debugPrint(
          '[ClassificationService] key-shape evidence: '
          '${(keyShapeScore * 100).toStringAsFixed(0)}%',
        );
      }
    }

    // A generic label such as "object" can be highly confident without giving
    // us a trustworthy SmartMatch category. Never auto-fill "Other" solely
    // because ML Kit was confident about that generic source label.
    final tier = category == 'Other'
        ? ConfidenceTier.low
        : _tierFor(effectiveConfidence);
    final material = _inferMaterial(labels);
    final subFeatures = _inferSubFeatures(labels);

    // Build distinct category suggestions (used by the medium tier).
    final seen = <String>{};
    final suggestions = <CategorySuggestion>[];
    if (keyShapeScore != null) {
      seen.add('Keys & Lanyards');
      suggestions.add(
        CategorySuggestion(
          category: 'Keys & Lanyards',
          confidence: keyShapeScore,
          rawLabel: 'key-shape evidence',
        ),
      );
    }
    if (keyShapeScore == null) {
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
    }

    final description = _buildDescription(
      colorName: colorName,
      material: material,
      noun: effectiveNoun,
      subFeatures: subFeatures,
    );

    return ClassificationResult(
      tier: tier,
      category: category,
      confidence: effectiveConfidence,
      rawLabel: effectiveRawLabel,
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

  Future<({List<ImageLabel> full, List<ImageLabel> object})> _labelImagePasses(
    File file,
  ) async {
    final full = await _labelImage(file);
    final crops = <File>[];
    try {
      final objectPasses = <List<ImageLabel>>[];
      for (final turns in const [0, 1, 3]) {
        final crop = await _createCenterObjectCrop(file, quarterTurns: turns);
        crops.add(crop);
        final labels = await _labelImage(crop);
        objectPasses.add(labels);
        if (kDebugMode) {
          debugPrint(
            '[ClassificationService] center rotation ${turns * 90}° labels: '
            '${_formatLabels(labels)}',
          );
        }
        if (labels.any(
          (label) =>
              label.confidence >= mediumThreshold &&
              mapLabelToCategory(label.label) == 'Keys & Lanyards',
        )) {
          break;
        }
      }
      return (full: full, object: _mergeLabelGroups(objectPasses));
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[ClassificationService] center crop skipped: $error');
      }
      return (full: full, object: <ImageLabel>[]);
    } finally {
      for (final crop in crops) {
        try {
          await crop.delete();
        } catch (_) {
          // A temporary crop must never make classification fail.
        }
      }
    }
  }

  /// Creates a portrait-friendly crop covering the middle 70% x 80% of the
  /// image. This removes most faces, hands and room background while retaining
  /// the item the capture UI asks the user to centre. Rotated variants make the
  /// labeler less sensitive to keys photographed vertically or upside-down.
  Future<File> _createCenterObjectCrop(
    File file, {
    int quarterTurns = 0,
  }) async {
    final codec = await ui.instantiateImageCodec(await file.readAsBytes());
    final frame = await codec.getNextFrame();
    final sourceImage = frame.image;
    try {
      final source = ui.Rect.fromLTWH(
        sourceImage.width * 0.15,
        sourceImage.height * 0.05,
        sourceImage.width * 0.70,
        sourceImage.height * 0.80,
      );
      const naturalWidth = 700;
      final naturalHeight = math.max(
        1,
        (naturalWidth * source.height / source.width).round(),
      );
      final turns = quarterTurns % 4;
      final outputWidth = turns.isOdd ? naturalHeight : naturalWidth;
      final outputHeight = turns.isOdd ? naturalWidth : naturalHeight;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      switch (turns) {
        case 1:
          canvas
            ..translate(outputWidth.toDouble(), 0)
            ..rotate(math.pi / 2);
        case 2:
          canvas
            ..translate(outputWidth.toDouble(), outputHeight.toDouble())
            ..rotate(math.pi);
        case 3:
          canvas
            ..translate(0, outputHeight.toDouble())
            ..rotate(-math.pi / 2);
      }
      canvas.drawImageRect(
        sourceImage,
        source,
        ui.Rect.fromLTWH(
          0,
          0,
          naturalWidth.toDouble(),
          naturalHeight.toDouble(),
        ),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final cropped = await recorder.endRecording().toImage(
        outputWidth,
        outputHeight,
      );
      try {
        final bytes = await cropped.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw StateError('Could not encode object crop');
        final path =
            '${Directory.systemTemp.path}${Platform.pathSeparator}'
            'smartmatch_object_${turns}_'
            '${DateTime.now().microsecondsSinceEpoch}.png';
        return File(path).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      } finally {
        cropped.dispose();
      }
    } finally {
      sourceImage.dispose();
      codec.dispose();
    }
  }

  ImageLabel? _firstMappedLabel(List<ImageLabel> labels) {
    // If the centre crop contains an explicit key/lock label, keep it even if
    // a secondary label such as "glasses" is slightly more confident.
    for (final label in labels) {
      if (label.confidence >= mediumThreshold &&
          mapLabelToCategory(label.label) == 'Keys & Lanyards') {
        return label;
      }
    }
    for (final label in labels) {
      if (mapLabelToCategory(label.label) != 'Other') return label;
    }
    return null;
  }

  List<ImageLabel> _mergeLabels(
    List<ImageLabel> full,
    List<ImageLabel> object,
  ) {
    final byName = <String, ImageLabel>{};
    for (final label in [...object, ...full]) {
      final key = label.label.trim().toLowerCase();
      final old = byName[key];
      if (old == null || label.confidence > old.confidence) {
        byName[key] = label;
      }
    }
    final merged = byName.values.toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    return merged;
  }

  List<ImageLabel> _mergeLabelGroups(List<List<ImageLabel>> groups) {
    var merged = <ImageLabel>[];
    for (final group in groups) {
      merged = _mergeLabels(merged, group);
    }
    return merged;
  }

  /// Returns a conservative medium-tier score when three independent labels
  /// describe the geometry of a key. Exposed only so the false-positive guards
  /// can be regression-tested without the native ML Kit runtime.
  @visibleForTesting
  static double? keyShapeEvidenceScore(Map<String, double> evidence) {
    double strongest(Iterable<String> names) {
      var result = 0.0;
      for (final entry in evidence.entries) {
        final normalized = entry.key
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
            .trim();
        if (names.contains(normalized)) result = math.max(result, entry.value);
      }
      return result;
    }

    final shaft = strongest(const ['nail', 'needle']);
    final bow = strongest(const [
      'goggles',
      'glasses',
      'sunglasses',
      'eyewear',
    ]);
    final reflectiveBody = strongest(const [
      'tableware',
      'metal',
      'silver',
      'hardware',
    ]);
    if (shaft < 0.30 || bow < 0.45 || reflectiveBody < 0.55) return null;

    // This is an ensemble evidence score, not a probability. Keep it in the
    // confirmation tier so the user must accept the suggested category.
    return ((shaft + bow + reflectiveBody) / 3).clamp(
      mediumThreshold,
      highThreshold - 0.01,
    );
  }

  String _formatLabels(List<ImageLabel> labels) => labels
      .take(10)
      .map(
        (label) =>
            '${label.label} ${(label.confidence * 100).toStringAsFixed(0)}%',
      )
      .join(', ');

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
      'keys',
      'lanyard',
      'keychain',
      'keyring',
      'car key',
      'house key',
      'fob',
      'lock',
      'padlock',
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
