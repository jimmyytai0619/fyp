import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileViewModel extends ChangeNotifier {
  // ── State ─────────────────────────────────────────────────────────────────

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _userName = '';
  String get userName => _userName;

  String _studentId = '';
  String get studentId => _studentId;

  String _email = '';
  String get email => _email;

  String _phone = '';
  String get phone => _phone;

  int _itemsFoundCount = 0;
  int get itemsFoundCount => _itemsFoundCount;

  int _itemsReturnedCount = 0;
  int get itemsReturnedCount => _itemsReturnedCount;

  bool _notificationsEnabled = true;
  bool get notificationsEnabled => _notificationsEnabled;

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  /// Returns the user's initials (up to 2 characters) for the avatar.
  String get initials {
    final parts = _userName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || _userName.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  /// Reads identity data from Supabase Auth metadata.
  /// Safe against null metadata — every field has a sensible fallback.
  Future<void> loadUserData() async {
    _setLoading(true);
    try {
      final user = Supabase.instance.client.auth.currentUser;

      _email = user?.email ?? 'No email on record';

      final meta = user?.userMetadata ?? {};
      _userName = (meta['full_name'] as String?)?.trim().isNotEmpty == true
          ? meta['full_name'] as String
          : 'Student User';
      _studentId = (meta['student_id'] as String?)?.trim().isNotEmpty == true
          ? meta['student_id'] as String
          : 'ID not set';
      _phone = (meta['phone'] as String?)?.trim().isNotEmpty == true
          ? meta['phone'] as String
          : 'Not provided';

      await fetchUserStatistics();
    } catch (e) {
      // Non-fatal: leave defaults in place so the UI never crashes.
      debugPrint('[ProfileViewModel] loadUserData error: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Fetches live statistics from Supabase.
  /// • itemsFoundCount   — rows in found_items reported by this user.
  /// • itemsReturnedCount — subset of those rows where is_returned = true.
  ///   Add a boolean column `is_returned` (default false) to found_items if
  ///   it does not yet exist, then flip it to true when an item is claimed.
  Future<void> fetchUserStatistics() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    final client = Supabase.instance.client;

    // Total items this user has reported as found.
    final foundResponse = await client
        .from('found_items')
        .select()
        .eq('user_id', uid)
        .count(CountOption.exact);
    _itemsFoundCount = foundResponse.count;
    notifyListeners();

    // Subset that have been successfully returned. Wrapped separately so a
    // missing `is_returned` column can't wipe out the found count above.
    try {
      final returnedResponse = await client
          .from('found_items')
          .select()
          .eq('user_id', uid)
          .eq('is_returned', true)
          .count(CountOption.exact);
      _itemsReturnedCount = returnedResponse.count;
    } catch (e) {
      _itemsReturnedCount = 0;
      debugPrint('[ProfileViewModel] returned-count skipped: $e');
    }
    notifyListeners();
  }

  // ── Toggle ─────────────────────────────────────────────────────────────────

  void toggleNotifications(bool value) {
    _notificationsEnabled = value;
    notifyListeners();
    // TODO: persist preference with shared_preferences or Supabase user metadata.
  }

  // ── Sign out ───────────────────────────────────────────────────────────────

  /// Signs the user out. Throws on failure so the View can show a Snackbar.
  Future<void> signOut() async {
    _setLoading(true);
    try {
      await Supabase.instance.client.auth.signOut();
    } on AuthException catch (e) {
      _setLoading(false);
      throw Exception(e.message);
    } catch (_) {
      _setLoading(false);
      throw Exception('Sign out failed. Please try again.');
    }
    // Keep isLoading true until the view navigates away.
  }
}
