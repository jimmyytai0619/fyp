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
    required String category,
    required String location,
    required String description,
    required String tags,
  }) async {
    if (_selectedImage == null) throw Exception('Please select an image.');
    if (location.trim().isEmpty) throw Exception('Location is required.');

    _setLoading(true);
    try {
      final tagList = tags
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      await ApiService().reportFoundItem(
        image: _selectedImage!,
        category: category,
        locationFound: location.trim(),
        description: description.trim(),
        tags: tagList,
      );
    } finally {
      _setLoading(false);
    }
  }
}
