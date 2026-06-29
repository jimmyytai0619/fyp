import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';

class ReportItemViewModel extends ChangeNotifier {
  final _picker = ImagePicker();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  File? _selectedImage;
  File? get selectedImage => _selectedImage;

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  Future<void> pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1080,
    );
    if (picked != null) {
      _selectedImage = File(picked.path);
      notifyListeners();
    }
  }

  void clearImage() {
    _selectedImage = null;
    notifyListeners();
  }

  Future<void> submitReport({
    required bool isLost,
    required String category,
    required String location,
    required String description,
    required String tags,
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

    _setLoading(true);
    try {
      final tagList = tags
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      if (isLost) {
        await ApiService().reportLostItem(
          image: _selectedImage,
          category: category,
          locationLost: location.trim(),
          description: description.trim(),
          tags: tagList,
        );
      } else {
        final newId = await ApiService().reportFoundItem(
          image: _selectedImage!,
          category: category,
          locationFound: location.trim(),
          description: description.trim(),
          tags: tagList,
          securityQuestion: securityQuestion?.trim(),
          securityAnswer: securityAnswer?.trim(),
        );
        // Fire the background matching agent (FR 4.3). Best-effort: if the AI
        // server is offline, the item is still saved — matching just won't run.
        try {
          await ApiService().ingestFoundItem(newId);
        } catch (_) {/* ignore — reporting already succeeded */}
      }
    } finally {
      _setLoading(false);
    }
  }
}
