import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';
import '../services/api_service.dart';

class NotificationsViewModel extends ChangeNotifier {
  // ── State ──────────────────────────────────────────────────────────────────

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<AppNotification> _notifications = [];
  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> fetchNotifications() async {
    _errorMessage = null;
    _setLoading(true);
    try {
      _notifications = await ApiService().getNotifications();
    } on PostgrestException catch (e) {
      _errorMessage = e.message;
      _notifications = [];
    } catch (e) {
      _errorMessage = 'Failed to load notifications. Please try again.';
      _notifications = [];
      debugPrint('[NotificationsViewModel] fetchNotifications error: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> markAsRead(String id) async {
    // Optimistic update — reflect "read" in the UI immediately.
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index == -1 || _notifications[index].isRead) return;

    _notifications = [
      for (final n in _notifications)
        if (n.id == id) n.copyWith(isRead: true) else n,
    ];
    notifyListeners();

    try {
      await ApiService().markNotificationRead(id);
    } on PostgrestException catch (e) {
      // Roll back the optimistic update on failure.
      _notifications = [
        for (final n in _notifications)
          if (n.id == id) n.copyWith(isRead: false) else n,
      ];
      _errorMessage = e.message;
      notifyListeners();
      debugPrint('[NotificationsViewModel] markAsRead error: $e');
    } catch (e) {
      _notifications = [
        for (final n in _notifications)
          if (n.id == id) n.copyWith(isRead: false) else n,
      ];
      _errorMessage = 'Could not mark notification as read.';
      notifyListeners();
      debugPrint('[NotificationsViewModel] markAsRead error: $e');
    }
  }
}
