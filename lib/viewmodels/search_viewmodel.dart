import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/match_result.dart';
import '../services/api_service.dart';

enum SearchState { idle, picking, loading, results, error }

class SearchViewModel extends ChangeNotifier {
  final _picker = ImagePicker();

  SearchState _state = SearchState.idle;
  SearchState get state => _state;

  File? _referenceImage;
  File? get referenceImage => _referenceImage;

  // Optional category hard-filter for the visual search.
  static const List<String> categories = [
    'Any Category',
    'Electronics',
    'IDs & Cards',
    'Bags & Wallets',
    'Keys & Lanyards',
    'Books & Stationery',
    'Clothing & Accessories',
    'Other',
  ];
  String _selectedCategory = 'Any Category';
  String get selectedCategory => _selectedCategory;

  void setCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  List<MatchResult> _searchResults = [];
  List<MatchResult> get searchResults => _searchResults;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  bool get isLoading => _state == SearchState.loading;

  void _setState(SearchState s) {
    _state = s;
    notifyListeners();
  }

  /// Returns true = granted, false = denied, null = permanently denied (open settings)
  Future<bool?> _requestPermission(ImageSource source) async {
    List<Permission> perms;

    if (source == ImageSource.camera) {
      perms = [Permission.camera];
    } else {
      if (Platform.isAndroid) {
        // Android 13+ needs photos, older needs storage
        perms = [Permission.photos, Permission.storage];
      } else {
        perms = [Permission.photos];
      }
    }

    for (final perm in perms) {
      var status = await perm.status;

      if (status.isPermanentlyDenied) return null; // must open settings

      if (!status.isGranted) {
        status = await perm.request();
      }

      if (status.isGranted) return true;
      if (status.isPermanentlyDenied) return null;
    }

    return false;
  }

  Future<void> pickImage(ImageSource source) async {
    final result = await _requestPermission(source);

    if (result == null) {
      // Permanently denied — open app settings so user can enable manually
      _errorMessage = 'OPEN_SETTINGS';
      _setState(SearchState.error);
      return;
    }

    if (result == false) {
      _errorMessage =
          'Permission denied. Please allow access when prompted.';
      _setState(SearchState.error);
      return;
    }

    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1080,
      );
      if (picked == null) return;
      _referenceImage = File(picked.path);
      _searchResults = [];
      _setState(SearchState.idle);
    } catch (e) {
      _errorMessage = 'Could not open camera/gallery. Please try again.';
      _setState(SearchState.error);
    }
  }

  void clearSearch() {
    _referenceImage = null;
    _searchResults = [];
    _errorMessage = '';
    _lostReportSaved = false;
    _setState(SearchState.idle);
  }

  // ── Save unmatched query as a Lost Report (FR 4.2) ──────────────────────────
  bool _savingLostReport = false;
  bool get savingLostReport => _savingLostReport;

  bool _lostReportSaved = false;
  bool get lostReportSaved => _lostReportSaved;

  /// Saves the current reference photo as an active Lost Report so the
  /// background agent can notify the user when a matching item is found later.
  /// Returns null on success or an error message on failure.
  Future<String?> saveReferenceAsLostReport() async {
    if (_referenceImage == null) return 'No reference photo to save.';
    _savingLostReport = true;
    notifyListeners();
    try {
      await ApiService().reportLostItem(
        image: _referenceImage,
        category: _selectedCategory == 'Any Category'
            ? 'Other'
            : _selectedCategory,
        locationLost: '',
        description: 'Saved from AI visual search',
        tags: const [],
      );
      _lostReportSaved = true;
      return null;
    } catch (e) {
      return 'Could not save lost report. Please try again.';
    } finally {
      _savingLostReport = false;
      notifyListeners();
    }
  }

  Future<void> executeVisualSearch() async {
    if (_referenceImage == null) return;
    _setState(SearchState.loading);
    try {
      final results = await ApiService().searchByImage(
        _referenceImage!,
        category:
            _selectedCategory == 'Any Category' ? null : _selectedCategory,
      );
      _searchResults = results
        ..sort((a, b) => b.confidenceScore.compareTo(a.confidenceScore));
      _setState(SearchState.results);
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _setState(SearchState.error);
    }
  }
}
