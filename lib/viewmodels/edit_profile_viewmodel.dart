import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditProfileViewModel extends ChangeNotifier {
  // ── State ──────────────────────────────────────────────────────────────────

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Holds the values that pre-fill the form on open.
  String? initialName;
  String? initialPhone;
  String? studentId;

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  // ── Load ───────────────────────────────────────────────────────────────────

  /// Reads the current user's metadata and populates the initial field values.
  /// Safe against null metadata — falls back to empty strings.
  Future<void> loadUserData() async {
    _setLoading(true);
    try {
      final meta =
          Supabase.instance.client.auth.currentUser?.userMetadata ?? {};

      initialName =
          (meta['full_name'] as String?)?.trim().isNotEmpty == true
              ? meta['full_name'] as String
              : '';

      initialPhone =
          (meta['phone'] as String?)?.trim().isNotEmpty == true
              ? meta['phone'] as String
              : '';

      studentId =
          (meta['student_id'] as String?)?.trim().isNotEmpty == true
              ? meta['student_id'] as String
              : 'Not set';
    } catch (e) {
      debugPrint('[EditProfileViewModel] loadUserData error: $e');
    } finally {
      _setLoading(false);
    }
  }

  // ── Update ─────────────────────────────────────────────────────────────────

  /// Pushes the new name and phone into Supabase Auth user metadata.
  /// Merges with the existing metadata map so other keys (e.g. student_id)
  /// are never overwritten.
  /// Throws a human-readable [Exception] that the View catches for Snackbars.
  Future<void> updateProfile({
    required String newName,
    required String newPhone,
  }) async {
    _setLoading(true);
    try {
      // Merge: keep all existing metadata keys, only update what changed.
      final existingMeta =
          Map<String, dynamic>.from(
        Supabase.instance.client.auth.currentUser?.userMetadata ?? {},
      );
      existingMeta['full_name'] = newName.trim();
      existingMeta['phone'] = newPhone.trim();

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: existingMeta),
      );

      // Update local cache so the form re-opens with correct values.
      initialName = newName.trim();
      initialPhone = newPhone.trim();
    } on AuthException catch (e) {
      throw Exception(_mapAuthError(e.message));
    } catch (e) {
      throw Exception('Could not save changes. Please try again.');
    } finally {
      _setLoading(false);
    }
  }

  // ── Error mapping ──────────────────────────────────────────────────────────

  String _mapAuthError(String raw) {
    final msg = raw.toLowerCase();
    if (msg.contains('network') || msg.contains('socket')) {
      return 'Network error. Please check your connection.';
    }
    if (msg.contains('not authenticated') || msg.contains('jwt')) {
      return 'Session expired. Please log in again.';
    }
    return raw;
  }
}
