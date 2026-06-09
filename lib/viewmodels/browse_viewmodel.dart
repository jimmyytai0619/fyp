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

  final List<String> categories = const [
    'All',
    'Electronics',
    'IDs & Cards',
    'Bags & Wallets',
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
      _foundItems = await ApiService().browseFoundItems(
        category: _selectedCategory == 'All' ? null : _selectedCategory,
      );
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
    notifyListeners();
    await fetchItems();
  }
}
