import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthViewModel extends ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  // Returns null on success, or a user-friendly error string on failure.
  Future<String?> login({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      return null;
    } on AuthException catch (e) {
      return _mapAuthError(e.message);
    } catch (e) {
      return 'An unexpected error occurred: $e';
    } finally {
      _setLoading(false);
    }
  }

  // Returns null on success, or a user-friendly error string on failure.
  Future<String?> register({
    required String email,
    required String password,
    required String fullName,
    required String studentId,
    required String phone,
  }) async {
    _setLoading(true);
    try {
      await Supabase.instance.client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'full_name': fullName.trim(),
          'student_id': studentId.trim(),
          'phone': phone.trim(),
        },
      );
      return null;
    } on AuthException catch (e) {
      return _mapAuthError(e.message);
    } catch (_) {
      return 'An unexpected error occurred. Please try again.';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  String _mapAuthError(String raw) {
    final msg = raw.toLowerCase();
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid email or password')) {
      return 'Incorrect email or password. Please try again.';
    }
if (msg.contains('user already registered') ||
        msg.contains('already been registered')) {
      return 'An account with this email already exists.';
    }
    if (msg.contains('password should be at least')) {
      return 'Password must be at least 6 characters long.';
    }
    if (msg.contains('unable to validate email address')) {
      return 'Please enter a valid email address.';
    }
    if (msg.contains('network') || msg.contains('socket')) {
      return 'Network error. Please check your connection and try again.';
    }
    return raw;
  }
}
