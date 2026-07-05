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

  static const _primaryBlue = Color(0xFF1565C0);
  static const _bgColor = Color(0xFFF0F4FF);

  @override
  void initState() {
    super.initState();
    _subscribeToNotifications();
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
                  onPressed: () => setState(() => _currentIndex = 1),
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
          // NotificationsViewModel is scoped to the Messages tab only.
          ChangeNotifierProvider(
            create: (_) => NotificationsViewModel(),
            child: const NotificationsView(),
          ),
          // ProfileViewModel is scoped to the Profile tab only.
          ChangeNotifierProvider(
            create: (_) => ProfileViewModel(),
            child: const ProfileView(),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
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

  static const _actions = [
    _ActionCard(
      icon: Icons.search_rounded,
      label: 'Find My Lost Item',
      description: 'Search now with a photo',
      color: Color(0xFF1565C0),
      route: 'search',
    ),
    _ActionCard(
      icon: Icons.add_a_photo_rounded,
      label: 'Report Found Item',
      description: "You found someone's lost item",
      color: Color(0xFF00897B),
      route: 'report',
    ),
    _ActionCard(
      icon: Icons.report_gmailerrorred_rounded,
      label: 'Report Lost Item',
      description: 'You lost item',
      color: Color(0xFFD81B60),
      route: 'report_lost',
    ),
    _ActionCard(
      icon: Icons.folder_open_rounded,
      label: 'Manage My Records',
      description: 'View & delete your reports',
      color: Color(0xFF6949FF),
      route: 'manage',
    ),
    _ActionCard(
      icon: Icons.verified_user_rounded,
      label: 'My Claims',
      description: 'Claims, approvals & chat',
      color: Color(0xFF00838F),
      route: 'claims',
    ),
    _ActionCard(
      icon: Icons.grid_view_rounded,
      label: 'Browse',
      description: 'See all found items',
      color: Color(0xFFE65100),
      route: 'browse',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(context)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _ActionCardWidget(card: _actions[i]),
                childCount: _actions.length,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 0.92,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _ActionCard {
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final String? route;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.route,
  });
}

class _ActionCardWidget extends StatelessWidget {
  final _ActionCard card;

  const _ActionCardWidget({required this.card});

  void _onTap(BuildContext context) {
    if (card.route == 'report') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ReportItemView()),
      );
    } else if (card.route == 'report_lost') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ReportItemView(isLost: true)),
      );
    } else if (card.route == 'search') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SearchView()),
      );
    } else if (card.route == 'manage') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (_) => ManageRecordsViewModel(),
            child: const ManageRecordsView(),
          ),
        ),
      );
    } else if (card.route == 'browse') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (_) => BrowseViewModel(),
            child: const BrowseView(),
          ),
        ),
      );
    } else if (card.route == 'claims') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (_) => ClaimsViewModel(),
            child: const ClaimsView(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _onTap(context),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: card.color.withValues(alpha: 0.15),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: card.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(card.icon, color: card.color, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                card.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A237E),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                card.description,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

