import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/item_report.dart';
import '../services/api_service.dart';

class ManageRecordsViewModel extends ChangeNotifier {
  // ── State ──────────────────────────────────────────────────────────────────

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<ItemReport> _myLostItems = [];
  List<ItemReport> get myLostItems => List.unmodifiable(_myLostItems);

  List<ItemReport> _myFoundItems = [];
  List<ItemReport> get myFoundItems => List.unmodifiable(_myFoundItems);

  // found_item_id → claim status (Pending / Verified / Rejected / Returned)
  Map<String, String> _foundClaimStatuses = {};
  Map<String, String> get foundClaimStatuses => _foundClaimStatuses;

  // ── Search / filter ─────────────────────────────────────────────────────────
  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  void setSearchQuery(String q) {
    _searchQuery = q.trim().toLowerCase();
    notifyListeners();
  }

  List<ItemReport> get filteredLostItems => _filter(_myLostItems);
  List<ItemReport> get filteredFoundItems => _filter(_myFoundItems);

  List<ItemReport> _filter(List<ItemReport> items) {
    if (_searchQuery.isEmpty) return List.unmodifiable(items);
    return items
        .where((i) =>
            i.category.toLowerCase().contains(_searchQuery) ||
            i.locationFound.toLowerCase().contains(_searchQuery) ||
            i.description.toLowerCase().contains(_searchQuery))
        .toList();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  // ── Data ───────────────────────────────────────────────────────────────────

  Future<void> fetchMyRecords() async {
    _errorMessage = null;
    _setLoading(true);
    try {
      final results = await Future.wait([
        ApiService().getMyLostReports(),
        ApiService().getMyFoundReports(),
      ]);
      _myLostItems = results[0];
      _myFoundItems = results[1];
      // Claim activity on my found items (best-effort — never blocks records).
      try {
        _foundClaimStatuses = await ApiService().getMyFoundClaimStatuses();
      } catch (e) {
        debugPrint('[ManageRecordsViewModel] claim statuses skipped: $e');
      }
    } on PostgrestException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Failed to load records. Please try again.';
      debugPrint('[ManageRecordsViewModel] fetchMyRecords error: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Deletes one of the user's own records and removes it from the local list.
  /// Throws on failure so the View can surface a message.
  Future<void> deleteRecord({
    required String id,
    required bool isLost,
  }) async {
    try {
      await ApiService().deleteReport(id: id, isLost: isLost);
      if (isLost) {
        _myLostItems = _myLostItems.where((e) => e.id != id).toList();
      } else {
        _myFoundItems = _myFoundItems.where((e) => e.id != id).toList();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[ManageRecordsViewModel] deleteRecord error: $e');
      throw Exception('Failed to delete the record. Please try again.');
    }
  }

  /// Closes (resolves/returns) or re-opens one of the user's own reports, then
  /// refreshes so its badge and matching state update.
  Future<void> resolveRecord({
    required String id,
    required bool isLost,
    bool reopen = false,
  }) async {
    try {
      await ApiService().resolveReport(id: id, isLost: isLost, reopen: reopen);
      await fetchMyRecords();
    } catch (e) {
      debugPrint('[ManageRecordsViewModel] resolveRecord error: $e');
      throw Exception('Could not update the report. Please try again.');
    }
  }

  /// Updates a record's editable fields, then refreshes the lists.
  Future<void> updateRecord({
    required String id,
    required bool isLost,
    required String category,
    required String location,
    required String description,
  }) async {
    try {
      await ApiService().updateReport(
        id: id,
        isLost: isLost,
        category: category,
        location: location,
        description: description,
      );
      await fetchMyRecords();
    } catch (e) {
      debugPrint('[ManageRecordsViewModel] updateRecord error: $e');
      throw Exception('Failed to update the record. Please try again.');
    }
  }
}
