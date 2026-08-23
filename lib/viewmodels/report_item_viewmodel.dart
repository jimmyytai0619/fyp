import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/classification_service.dart';

class ReportItemViewModel extends ChangeNotifier {
  final _picker = ImagePicker();
  final ClassificationService _classifier = ClassificationService();
  bool _disposed = false;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  File? _selectedImage;
  File? get selectedImage => _selectedImage;

  // ── On-device AI classification state (Modules 2 & 3) ──────────────────────
  bool _isClassifying = false;
  bool get isClassifying => _isClassifying;

  ClassificationResult? _classification;
  ClassificationResult? get classification => _classification;

  // Convenience accessors for the View (Algorithm 4.7.1 three-tier handling).
  ConfidenceTier? get tier => _classification?.tier;
  bool get isHighConfidence => _classification?.isHigh ?? false;
  bool get isMediumConfidence => _classification?.isMedium ?? false;
  bool get needsManualReview => _classification?.needsManualReview ?? false;
  List<CategorySuggestion> get suggestions =>
      _classification?.suggestions ?? const [];
  String get generatedDescription => _classification?.description ?? '';
  String get colorName => _classification?.colorName ?? 'Unknown';

  void _setLoading(bool v) {
    _isLoading = v;
    _notifyIfActive();
  }

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }

  Future<void> pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1080,
    );
    if (picked != null && !_disposed) {
      _selectedImage = File(picked.path);
      _notifyIfActive();
      await _classifyImage();
    }
  }

  /// Runs ML Kit on the selected image and stores the suggestion. Best-effort:
  /// if classification fails, reporting still works with manual category entry.
  Future<void> _classifyImage() async {
    if (_disposed) return;
    final file = _selectedImage;
    if (file == null) return;
    _isClassifying = true;
    _notifyIfActive();
    try {
      final result = await _classifier.classify(file);
      if (!_disposed) _classification = result;
    } catch (e, stackTrace) {
      debugPrint('[ReportItemViewModel] classification failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      _classification = null; // fall back to manual selection
    } finally {
      _isClassifying = false;
      _notifyIfActive();
    }
  }

  void clearImage() {
    _selectedImage = null;
    _classification = null;
    _notifyIfActive();
  }

  Future<void> submitReport({
    required bool isLost,
    required String category,
    required String location,
    required String description,
    required String tags,
    DateTime? dateFound,
    String? securityQuestion,
    String? securityAnswer,
  }) async {
    // Found items must have a photo (it's the basis for AI matching); lost
    // items may be reported without one.
    if (!isLost && _selectedImage == null) {
      throw Exception('Please select an image.');
    }
    if (!isLost && location.trim().isEmpty) {
      throw Exception('Location is required.');
    }
    // FR 2.5 — found items require a category, description and date found.
    if (!isLost) {
      if (category.trim().isEmpty || category == 'Unrecognized') {
        throw Exception('Please choose an item category.');
      }
      if (description.trim().isEmpty) {
        throw Exception('Please enter an item description.');
      }
      if (dateFound == null) {
        throw Exception('Please select the date the item was found.');
      }
    }

    // Lost items require at least a category and a description so the report is
    // useful for matching.
    if (isLost) {
      if (category.trim().isEmpty || category == 'Unrecognized') {
        throw Exception('Please choose an item category.');
      }
      if (description.trim().isEmpty) {
        throw Exception('Please enter a description of your lost item.');
      }
    }
    _setLoading(true);
    try {
      final tagList = tags
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      if (isLost) {
        final newId = await ApiService().reportLostItem(
          image: _selectedImage,
          category: category,
          locationLost: location.trim(),
          description: description.trim(),
          tags: tagList,
        );
        // Reverse-direction matching (FR 4.3): if this lost item has a photo,
        // check it against items already reported found. Best-effort.
        if (_selectedImage != null) {
          try {
            await ApiService().ingestLostItem(newId);
          } catch (_) {
            /* ignore — reporting already succeeded */
          }
        }
      } else {
        // Persist the found-date inside the description so no DB schema change
        // is required. (To promote it to a column, add `date_found` to
        // found_items and pass it through ApiService.reportFoundItem.)
        final composedDescription = dateFound == null
            ? description.trim()
            : '${description.trim()}\n(Found on: ${_formatDate(dateFound)})';

        final newId = await ApiService().reportFoundItem(
          image: _selectedImage!,
          category: category,
          locationFound: location.trim(),
          description: composedDescription,
          tags: tagList,
          securityQuestion: securityQuestion?.trim(),
          securityAnswer: securityAnswer?.trim(),
        );
        // Fire the background matching agent (FR 4.3). Best-effort.
        try {
          await ApiService().ingestFoundItem(newId);
        } catch (_) {
          /* ignore — reporting already succeeded */
        }
      }
    } finally {
      _setLoading(false);
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _disposed = true;
    _classifier.dispose();
    super.dispose();
  }
}
