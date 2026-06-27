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
}
