import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthViewModel extends ChangeNotifier {
  static const String _rememberMeKey = 'remembered_email';
  static const String _autoLoginKey = 'auto_login';

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  // Returns true if the user opted for auto-login.
  Future<bool> isAutoLoginEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoLoginKey) ?? false;
  }

  // Returns the saved email if "Remember Me" was checked previously.
  Future<String?> getRememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_rememberMeKey);
  }

  // Returns null on success, or a user-friendly error string on failure.
  Future<String?> login({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    _setLoading(true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      // Handle "Remember Me" persistence
      final prefs = await SharedPreferences.getInstance();
      if (rememberMe) {
        await prefs.setString(_rememberMeKey, email.trim());
        await prefs.setBool(_autoLoginKey, true);
      } else {
        await prefs.remove(_rememberMeKey);
        await prefs.setBool(_autoLoginKey, false);
      }

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

  // Verifies the 6-digit signup OTP.
  // Returns true on success; throws a user-friendly error message on failure.
  Future<bool> verifyOtp(String email, String otp) async {
    _setLoading(true);
    try {
      await Supabase.instance.client.auth.verifyOTP(
        email: email.trim(),
        token: otp.trim(),
        type: OtpType.signup,
      );
      return true;
    } on AuthException catch (e) {
      throw _mapAuthError(e.message);
    } catch (_) {
      throw 'An unexpected error occurred. Please try again.';
    } finally {
      _setLoading(false);
    }
  }

  // Returns null on success, or a user-friendly error string on failure.
  Future<String?> forgotPassword({required String email}) async {
    _setLoading(true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: 'smartmatch://reset-password',
      );
      return null;
    } on AuthException catch (e) {
      return _mapAuthError(e.message);
    } catch (e) {
      return 'An unexpected error occurred. Please try again.';
    } finally {
      _setLoading(false);
    }
  }

  // Returns null on success, or a user-friendly error string on failure.
  Future<String?> updatePassword({required String newPassword}) async {
    _setLoading(true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      return null;
    } on AuthException catch (e) {
      return _mapAuthError(e.message);
    } catch (e) {
      return 'An unexpected error occurred. Please try again.';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoLoginKey, false); // Disable auto-login on logout
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
