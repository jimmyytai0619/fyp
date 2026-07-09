import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_notification.dart';
import '../../models/item_report.dart';
import '../../models/match_result.dart';
import '../../services/api_service.dart';
import '../../viewmodels/notifications_viewmodel.dart';
import '../search/item_detail_view.dart';

class NotificationsView extends StatefulWidget {
  const NotificationsView({super.key});

  @override
  State<NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends State<NotificationsView> {
  static const _primaryBlue = Color(0xFF1565C0);
  static const _unreadTint = Color(0xFFE8F0FE);

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      context.read<NotificationsViewModel>().fetchNotifications();
    });
  }

  /// Marks the alert read and, if it points to a found item, opens its detail
  /// page so the user can claim it.
  Future<void> _openNotification(
      BuildContext context, NotificationsViewModel vm, AppNotification n) async {
    if (!n.isRead) vm.markAsRead(n.id);
    if (n.itemId == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    ItemReport? item;
    try {
      item = await ApiService().getFoundItemById(n.itemId!);
    } catch (_) {
      item = null;
    }

    if (!context.mounted) return;
    Navigator.of(context).pop(); // close the loader

    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That item is no longer available.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final match = MatchResult(
      id: item.id,
      imageUrl: item.imageUrl,
      category: item.category,
      locationFound: item.locationFound,
      description: item.description,
      tags: const [],
      confidenceScore: 0,
      createdAt: item.createdAt,
    );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ItemDetailView(item: match)),
    );
  }

  Future<void> _confirmClear(
      BuildContext context, NotificationsViewModel vm) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear all notifications?'),
        content:
            const Text('This removes all your alerts and cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF757575))),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear all',
                style: TextStyle(
                    color: Color(0xFFD32F2F), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok == true) vm.clearAll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Messages & Alerts',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          Consumer<NotificationsViewModel>(
            builder: (ctx, vm, child) {
              if (vm.notifications.isEmpty) return const SizedBox.shrink();
              return PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) {
                  if (value == 'read') {
                    vm.markAllRead();
                  } else if (value == 'clear') {
                    _confirmClear(ctx, vm);
                  }
                },
                itemBuilder: (_) => [
                  if (vm.unreadCount > 0)
                    const PopupMenuItem(
                      value: 'read',
                      child: Row(children: [
                        Icon(Icons.done_all_rounded, size: 20),
                        SizedBox(width: 10),
                        Text('Mark all as read'),
                      ]),
                    ),
                  const PopupMenuItem(
                    value: 'clear',
                    child: Row(children: [
                      Icon(Icons.delete_sweep_outlined, size: 20),
                      SizedBox(width: 10),
                      Text('Clear all'),
                    ]),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Consumer<NotificationsViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) {
            return const Center(
              child: CircularProgressIndicator(color: _primaryBlue),
            );
          }

          if (vm.errorMessage != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFFB00020),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  content: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(vm.errorMessage!,
                            style: const TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              );
            });
          }

          if (vm.notifications.isEmpty) {
            return const _EmptyState();
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            itemCount: vm.notifications.length,
            separatorBuilder: (ctx, i) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _NotificationCard(
              notification: vm.notifications[i],
              unreadTint: _unreadTint,
              onTap: () =>
                  _openNotification(context, vm, vm.notifications[i]),
            ),
          );
        },
      ),
    );
  }
}

// ── Notification Card ─────────────────────────────────────────────────────────

class _NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final Color unreadTint;
  final VoidCallback onTap;

  const _NotificationCard({
    required this.notification,
    required this.unreadTint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUnread = !notification.isRead;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: isUnread ? unreadTint : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon container
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isUnread
                      ? const Color(0xFF1565C0).withValues(alpha: 0.12)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isUnread
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_outlined,
                  color: isUnread
                      ? const Color(0xFF1565C0)
                      : Colors.grey.shade400,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isUnread
                                  ? const Color(0xFF1A237E)
                                  : const Color(0xFF546E7A),
                            ),
                          ),
                        ),
                        if (isUnread)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF1565C0),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.message,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatDate(notification.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.mark_email_read_outlined,
                size: 42,
                color: const Color(0xFF1565C0).withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'You have no new messages.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Color(0xFF78909C),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
