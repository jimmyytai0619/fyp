import 'package:flutter/foundation.dart';

import '../models/item_report.dart';
import '../services/api_service.dart';
import 'browse_viewmodel.dart';

/// Aggregated campus lost-and-found stats for the Analytics dashboard.
/// Built from found-item data (readable by all users), so it works without
/// admin access.
class AnalyticsViewModel extends ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  int _total = 0;
  int get total => _total;

  int _returned = 0;
  int get returned => _returned;

  /// 0–100. Share of found items that were handed back.
  double get returnRate => _total == 0 ? 0 : (_returned / _total) * 100;

  /// Category → count, highest first.
  List<MapEntry<String, int>> _byCategory = [];
  List<MapEntry<String, int>> get byCategory => _byCategory;

  /// Building → count, highest first (the "hotspots").
  List<MapEntry<String, int>> _byBuilding = [];
  List<MapEntry<String, int>> get byBuilding => _byBuilding;

  Future<void> load() async {
    _errorMessage = null;
    _isLoading = true;
    notifyListeners();
    try {
      final items = await ApiService().browseFoundItems(); // all found items
      _compute(items);
    } catch (e) {
      _errorMessage = 'Could not load analytics. Please try again.';
      debugPrint('[AnalyticsViewModel] load error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _compute(List<ItemReport> items) {
    _total = items.length;
    _returned = items.where((i) => i.isReturned).length;

    final cat = <String, int>{};
    final bld = <String, int>{};
    for (final i in items) {
      cat[i.category] = (cat[i.category] ?? 0) + 1;
      final b = BrowseViewModel.buildingOf(i.locationFound);
      if (b.isNotEmpty) bld[b] = (bld[b] ?? 0) + 1;
    }
    _byCategory = cat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _byBuilding = bld.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }
}
