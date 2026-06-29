import 'package:flutter/foundation.dart';

import '../models/claim.dart';
import '../services/api_service.dart';

class ClaimsViewModel extends ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<Claim> _myClaims = [];
  List<Claim> get myClaims => List.unmodifiable(_myClaims);

  List<Claim> _requests = [];
  List<Claim> get requests => List.unmodifiable(_requests);

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  Future<void> fetchAll() async {
    _errorMessage = null;
    _setLoading(true);
    try {
      final res = await Future.wait([
        ApiService().getMyClaims(),
        ApiService().getClaimRequests(),
      ]);
      _myClaims = res[0];
      _requests = res[1];
    } catch (e) {
      _errorMessage = 'Failed to load claims. Please try again.';
      debugPrint('[ClaimsViewModel] fetchAll error: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> approve(String claimId) => _update(claimId, 'Verified');
  Future<void> reject(String claimId) => _update(claimId, 'Rejected');
  Future<void> markReturned(String claimId) => _update(claimId, 'Returned');

  Future<void> _update(String claimId, String status) async {
    try {
      await ApiService().updateClaimStatus(claimId, status);
      await fetchAll();
    } catch (e) {
      _errorMessage = 'Could not update the claim. Please try again.';
      notifyListeners();
    }
  }
}
