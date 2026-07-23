import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../viewmodels/browse_viewmodel.dart';
import '../../viewmodels/claims_viewmodel.dart';
import '../../viewmodels/manage_records_viewmodel.dart';
import '../../viewmodels/notifications_viewmodel.dart';
import '../../viewmodels/profile_viewmodel.dart';
import '../browse/browse_view.dart';
import '../claims/claims_view.dart';
import '../manage_records/manage_records_view.dart';
import '../notifications/notifications_view.dart';
import '../profile/profile_view.dart';
import '../report_item/report_item_view.dart';
import '../search/search_view.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  int _currentIndex = 0;
  RealtimeChannel? _notifChannel;

  // Shared so the realtime alert and the Messages tab use the same list.
  final NotificationsViewModel _notifVM = NotificationsViewModel();

  // Shared so we can refresh contribution stats when the Profile tab is opened.
  final ProfileViewModel _profileVM = ProfileViewModel();

  static const _primaryBlue = Color(0xFF1565C0);
  static const _bgColor = Color(0xFFF0F4FF);

  @override
  void initState() {
    super.initState();
    _notifVM.fetchNotifications();
    _subscribeToNotifications();
  }

  void _openMessagesTab() {
    setState(() => _currentIndex = 1);
    _notifVM.fetchNotifications(); // pull the latest so it isn't stale
  }

  /// FR 4.4 — Listens over Supabase Realtime (WebSockets) for new notification
  /// rows targeting this user and shows an instant in-app alert.
  void _subscribeToNotifications() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    _notifChannel = Supabase.instance.client
        .channel('notifications_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (payload) {
            final title =
                (payload.newRecord['title'] as String?) ?? 'New match found';
            // Refresh the inbox list immediately so the new alert is there.
            _notifVM.fetchNotifications();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.notifications_active_rounded,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(title)),
                  ],
                ),
                backgroundColor: _primaryBlue,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'VIEW',
                  textColor: Colors.white,
                  onPressed: _openMessagesTab,
                ),
              ),
            );
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_notifChannel != null) {
      Supabase.instance.client.removeChannel(_notifChannel!);
    }
    _notifVM.dispose();
    _profileVM.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const _HomeTab(),
          // Shared NotificationsViewModel (owned by this State) so live alerts
          // and the Messages tab stay in sync.
          ChangeNotifierProvider.value(
            value: _notifVM,
            child: const NotificationsView(),
          ),
          // Shared ProfileViewModel so contribution stats refresh on tab open.
          ChangeNotifierProvider.value(
            value: _profileVM,
            child: const ProfileView(),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          setState(() => _currentIndex = i);
          if (i == 1) _notifVM.fetchNotifications(); // refresh inbox on open
          if (i == 2) _profileVM.loadUserData(); // refresh stats on open
        },
        backgroundColor: Colors.white,
        indicatorColor: _primaryBlue.withValues(alpha: 0.12),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: _primaryBlue),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon:
                Icon(Icons.chat_bubble_rounded, color: _primaryBlue),
            label: 'Messages',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded, color: _primaryBlue),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ── Home Tab ─────────────────────────────────────────────────────────────────

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(context)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionLabel(text: 'Primary Actions'),
                  const SizedBox(height: 12),
                  _BigActionCard(
                    icon: Icons.add_a_photo_rounded,
                    label: 'Report Found Item',
                    description: "Help someone find their lost belongings",
                    color: const Color(0xFF00897B),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ReportItemView()),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _GroupedLostCard(),
                  const SizedBox(height: 28),
                  const _SectionLabel(text: 'More Actions'),
                  const SizedBox(height: 12),
                  _RectActionCard(
                    icon: Icons.folder_open_rounded,
                    label: 'Manage My Records',
                    description: 'View and manage your reports',
                    color: const Color(0xFF6949FF),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChangeNotifierProvider(
                          create: (_) => ManageRecordsViewModel(),
                          child: const ManageRecordsView(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _RectActionCard(
                    icon: Icons.verified_user_rounded,
                    label: 'My Claims',
                    description: 'Track your claims and handovers',
                    color: const Color(0xFF00838F),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChangeNotifierProvider(
                          create: (_) => ClaimsViewModel(),
                          child: const ClaimsView(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _RectActionCard(
                    icon: Icons.grid_view_rounded,
                    label: 'Browse Items',
                    description: 'See what has been found on campus',
                    color: const Color(0xFFE65100),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChangeNotifierProvider(
                          create: (_) => BrowseViewModel(),
                          child: const BrowseView(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.manage_search_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 10),
              const Text(
                'SmartMatch',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'What would you like to do?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Select an action below to get started.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: Colors.blueGrey.shade700,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ── Large Card (Found) ────────────────────────────────────────────────────────

class _BigActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const _BigActionCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: Colors.white, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Grouped Card (Lost) ───────────────────────────────────────────────────────

class _GroupedLostCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFD81B60);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.report_gmailerrorred_rounded,
                  color: accent, size: 24),
              const SizedBox(width: 8),
              const Text(
                'I Lost Something',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0D2B6B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _LostSubAction(
            icon: Icons.search_rounded,
            label: 'Find My Lost Item',
            sublabel: 'Visual Search with AI',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchView()),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          _LostSubAction(
            icon: Icons.edit_note_rounded,
            label: 'Report Lost Item',
            sublabel: 'Submit a manual report',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const ReportItemView(isLost: true)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LostSubAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback onTap;

  const _LostSubAction({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFD81B60).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_forward_rounded,
                color: Color(0xFFD81B60), size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A237E),
                  ),
                ),
                Text(
                  sublabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.grey),
        ],
      ),
    );
  }
}

// ── Rectangular Action Card ──────────────────────────────────────────────────

class _RectActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const _RectActionCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

