import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/match_result.dart';
import '../services/api_service.dart';

enum SearchState { idle, picking, loading, results, error }

class SearchViewModel extends ChangeNotifier {
  final _picker = ImagePicker();

  SearchState _state = SearchState.idle;
  SearchState get state => _state;

  File? _referenceImage;
  File? get referenceImage => _referenceImage;

  List<MatchResult> _searchResults = [];
  List<MatchResult> get searchResults => _searchResults;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  bool get isLoading => _state == SearchState.loading;

  void _setState(SearchState s) {
    _state = s;
    notifyListeners();
  }

  Future<void> pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1080,
    );
    if (picked == null) return;
    _referenceImage = File(picked.path);
    _searchResults = [];
    _setState(SearchState.idle);
  }

  void clearSearch() {
    _referenceImage = null;
    _searchResults = [];
    _errorMessage = '';
    _setState(SearchState.idle);
  }

  Future<void> executeVisualSearch() async {
    if (_referenceImage == null) return;
    _setState(SearchState.loading);
    try {
      final results = await ApiService().searchByImage(_referenceImage!);
      _searchResults = results
        ..sort((a, b) => b.confidenceScore.compareTo(a.confidenceScore));
      _setState(SearchState.results);
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _setState(SearchState.error);
    }
  }
}
