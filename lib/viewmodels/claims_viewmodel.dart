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

  /// Finder approves the claim → claimant gets a "Claim approved" notification.
  Future<void> approve(String claimId) => _decide(claimId, 'Verified');

  /// Finder rejects the claim → claimant gets a "Claim not approved" notification.
  Future<void> reject(String claimId) => _decide(claimId, 'Rejected');

  /// Runs the server-side decision so the claimant is notified (see
  /// ApiService.decideClaim). Falls back to a plain status update only if the
  /// RPC itself is unreachable.
  Future<void> _decide(String claimId, String status) async {
    try {
      final result = await ApiService().decideClaim(claimId, status);
      // 'OK' = status changed + claimant notified. Anything else means the RPC
      // ran but reported a problem (e.g. NOT_FINDER) — logged for diagnosis.
      debugPrint('[ClaimsViewModel] decide_claim result: $result');
      await fetchAll();
    } catch (e) {
      _errorMessage = 'Could not update the claim. Please try again.';
      notifyListeners();
      debugPrint('[ClaimsViewModel] decide error: $e');
    }
  }

  /// Marks the handover complete. Runs server-side so it also flags the found
  /// item returned (contribution stat) AND notifies the other party.
  Future<void> markReturned(Claim claim) async {
    try {
      final result = await ApiService().markReturnedClaim(claim.id);
      debugPrint('[ClaimsViewModel] mark_returned result: $result');
      await fetchAll();
    } catch (e) {
      _errorMessage = 'Could not update the claim. Please try again.';
      notifyListeners();
      debugPrint('[ClaimsViewModel] markReturned error: $e');
    }
  }

}
