import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/item_report.dart';
import '../services/api_service.dart';

class BrowseViewModel extends ChangeNotifier {
  // ── State ──────────────────────────────────────────────────────────────────

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<ItemReport> _foundItems = [];
  List<ItemReport> get foundItems => List.unmodifiable(_foundItems);

  String _selectedCategory = 'All';
  String get selectedCategory => _selectedCategory;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  final List<String> categories = const [
    'All',
    'Electronics',
    'IDs & Cards',
    'Bags & Wallets',
    'Keys & Lanyards',
    'Books & Stationery',
    'Clothing & Accessories',
    'Other',
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
        _foundItems =
            await ApiService().searchFoundItemsByText(_searchQuery);
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
