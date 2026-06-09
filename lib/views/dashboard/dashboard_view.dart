import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/browse_viewmodel.dart';
import '../../viewmodels/manage_records_viewmodel.dart';
import '../../viewmodels/notifications_viewmodel.dart';
import '../../viewmodels/profile_viewmodel.dart';
import '../browse/browse_view.dart';
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

  static const _primaryBlue = Color(0xFF1565C0);
  static const _bgColor = Color(0xFFF0F4FF);

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

  static const _primaryBlue = Color(0xFF1565C0);

  static const _actions = [
    _ActionCard(
      icon: Icons.search_rounded,
      label: 'Find My\nLost Item',
      color: Color(0xFF1565C0),
      route: 'search',
    ),
    _ActionCard(
      icon: Icons.add_a_photo_rounded,
      label: 'Report\nFound Item',
      color: Color(0xFF00897B),
      route: 'report',
    ),
    _ActionCard(
      icon: Icons.folder_open_rounded,
      label: 'Manage\nMy Records',
      color: Color(0xFF6949FF),
      route: 'manage',
    ),
    _ActionCard(
      icon: Icons.grid_view_rounded,
      label: 'Browse',
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
                childAspectRatio: 1.05,
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
  final Color color;
  final String? route;

  const _ActionCard({
    required this.icon,
    required this.label,
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: card.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(card.icon, color: card.color, size: 30),
            ),
            const SizedBox(height: 14),
            Text(
              card.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A237E),
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

