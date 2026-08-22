import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/item_report.dart';
import '../services/api_service.dart';
import '../services/classification_service.dart';

class BrowseViewModel extends ChangeNotifier {
  // ── State ──────────────────────────────────────────────────────────────────

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<ItemReport> _foundItems = [];
  List<ItemReport> get foundItems => List.unmodifiable(_foundItems);

  /// How many days an unclaimed found item stays visible before it's treated as
  /// expired/archived (keeps Browse clean). FR — auto-expire.
  static const int expiryDays = 100;

  String _selectedCategory = 'All';
  String get selectedCategory => _selectedCategory;

  // ── Filters (applied client-side over the loaded list) ──────────────────────
  String _selectedBuilding = 'All';
  String get selectedBuilding => _selectedBuilding;

  /// 0 = any time; otherwise only items from the last N days.
  int _maxAgeDays = 0;
  int get maxAgeDays => _maxAgeDays;

  /// Building (area) part of a composed "Building — Spot" location string.
  static String buildingOf(String location) {
    if (location.isEmpty) return '';
    for (final sep in ['—', ' - ', '-']) {
      final i = location.indexOf(sep);
      if (i > 0) return location.substring(0, i).trim();
    }
    return location.trim();
  }

  /// Buildings present in the current results (for the filter dropdown).
  List<String> get buildings {
    final set = <String>{};
    for (final i in _foundItems) {
      final b = buildingOf(i.locationFound);
      if (b.isNotEmpty) set.add(b);
    }
    final list = set.toList()..sort();
    return ['All', ...list];
  }

  void setBuilding(String b) {
    _selectedBuilding = b;
    notifyListeners();
  }

  void setMaxAgeDays(int days) {
    _maxAgeDays = days;
    notifyListeners();
  }

  /// The list Browse actually shows: excludes returned + expired items and
  /// applies the building/date filters.
  List<ItemReport> get filteredItems {
    final now = DateTime.now();
    return _foundItems.where((i) {
      if (i.isReturned) return false; // already handed back
      if (now.difference(i.createdAt).inDays > expiryDays) return false; // expired
      if (_selectedBuilding != 'All' &&
          buildingOf(i.locationFound) != _selectedBuilding) {
        return false;
      }
      if (_maxAgeDays > 0 && now.difference(i.createdAt).inDays > _maxAgeDays) {
        return false;
      }
      return true;
    }).toList();
  }

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  final List<String> categories = const [
    'All',
    ...ClassificationService.categories,
  ];

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> fetchItems() async {
    _errorMessage = null;
    _setLoading(true);
    try {
      if (_searchQuery.isNotEmpty) {
        // FR 4.1 — Smart text search overrides the category filter.
        _foundItems = await ApiService().searchFoundItemsByText(_searchQuery);
      } else {
        _foundItems = await ApiService().browseFoundItems(
          category: _selectedCategory == 'All' ? null : _selectedCategory,
        );
      }
    } on PostgrestException catch (e) {
      _errorMessage = e.message;
      _foundItems = [];
    } catch (e) {
      _errorMessage = 'Failed to load items. Please try again.';
      _foundItems = [];
      debugPrint('[BrowseViewModel] fetchItems error: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> setCategory(String category) async {
    if (_selectedCategory == category) return;
    _selectedCategory = category;
    _searchQuery = ''; // picking a category clears an active text search
    notifyListeners();
    await fetchItems();
  }

  /// FR 4.1 — run a keyword search; an empty query reverts to category browsing.
  Future<void> setSearchQuery(String query) async {
    _searchQuery = query.trim();
    notifyListeners();
    await fetchItems();
  }
}
