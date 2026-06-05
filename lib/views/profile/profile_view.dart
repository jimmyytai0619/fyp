import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/profile_viewmodel.dart';
import 'edit_profile_view.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  // ── Constants ─────────────────────────────────────────────────────────────

  static const _primaryBlue = Color(0xFF1565C0);
  static const _darkBlue = Color(0xFF0D2B6B);
  static const _bgColor = Color(0xFFF0F4FF);
  static const _cardColor = Colors.white;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Defer so the widget tree is fully built before we call notifyListeners.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ProfileViewModel>().loadUserData();
    });
  }

  // ── Sign-out handler ──────────────────────────────────────────────────────

  Future<void> _handleSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Sign Out',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await context.read<ProfileViewModel>().signOut();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
    } catch (e) {
      if (!mounted) return;
      _showSnackbar(context,
          e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  void _showSnackbar(BuildContext context, String msg,
      {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg)),
        ]),
        backgroundColor:
            isError ? const Color(0xFFD32F2F) : const Color(0xFF2E7D32),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfileViewModel>(
      builder: (context, vm, _) {
        if (vm.isLoading && vm.userName.isEmpty) {
          return const Scaffold(
            backgroundColor: _bgColor,
            body: Center(
              child: CircularProgressIndicator(color: _primaryBlue),
            ),
          );
        }

        return Scaffold(
          backgroundColor: _bgColor,
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(vm)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 24),
                        _buildStatsCard(vm),
                        const SizedBox(height: 24),
                        _buildSectionLabel('Settings'),
                        const SizedBox(height: 10),
                        _buildSettingsCard(context, vm),
                        const SizedBox(height: 24),
                        _buildSignOutButton(context, vm),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(ProfileViewModel vm) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        children: [
          // Avatar
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.2),
              border: Border.all(color: Colors.white54, width: 2.5),
            ),
            child: Center(
              child: Text(
                vm.initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Name
          Text(
            vm.userName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),

          const SizedBox(height: 6),

          // Student ID chip
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              vm.studentId,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Email
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.email_outlined,
                  size: 14, color: Colors.white70),
              const SizedBox(width: 5),
              Text(
                vm.email,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Stats card ──────────────────────────────────────────────────────────────

  Widget _buildStatsCard(ProfileViewModel vm) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _primaryBlue.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card heading
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.volunteer_activism_rounded,
                    color: _primaryBlue, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'Campus Contributions',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: _darkBlue,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(height: 1, color: Color(0xFFEEF0F8)),
          const SizedBox(height: 20),

          // Stats row
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _statCell(
                    icon: Icons.find_in_page_rounded,
                    iconColor: const Color(0xFF00897B),
                    bgColor: const Color(0xFFE0F2F1),
                    count: vm.itemsFoundCount,
                    label: 'Items Found',
                  ),
                ),
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: const Color(0xFFEEF0F8),
                ),
                Expanded(
                  child: _statCell(
                    icon: Icons.check_circle_outline_rounded,
                    iconColor: const Color(0xFF6949FF),
                    bgColor: const Color(0xFFEDE7FF),
                    count: vm.itemsReturnedCount,
                    label: 'Items Returned',
                  ),
                ),
              ],
            ),
          ),

        ],
      ),
    );
  }

  Widget _statCell({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required int count,
    required String label,
  }) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration:
              BoxDecoration(color: bgColor, shape: BoxShape.circle),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(height: 10),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: _darkBlue,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: Color(0xFF607D8B),
          ),
        ),
      ],
    );
  }

  // ── Settings card ───────────────────────────────────────────────────────────

  Widget _buildSectionLabel(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF9E9E9E),
          letterSpacing: 1.2,
        ),
      );

  Widget _buildSettingsCard(BuildContext context, ProfileViewModel vm) {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _settingsTile(
            icon: Icons.edit_outlined,
            iconBg: const Color(0xFFE3F2FD),
            iconColor: _primaryBlue,
            title: 'Edit Profile',
            trailing: const Icon(Icons.chevron_right_rounded,
                color: Color(0xFFBDBDBD)),
            onTap: () async {
              // Push EditProfileView and refresh local data if a save happened.
              final didSave = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                    builder: (_) => const EditProfileView()),
              );
              if ((didSave ?? false) && context.mounted) {
                context.read<ProfileViewModel>().loadUserData();
              }
            },
            showDivider: true,
          ),
          _settingsTile(
            icon: Icons.notifications_outlined,
            iconBg: const Color(0xFFFFF8E1),
            iconColor: const Color(0xFFF57F17),
            title: 'Push Notifications',
            subtitle: 'Get alerts from the background AI agent',
            trailing: Switch(
              value: vm.notificationsEnabled,
              onChanged: vm.toggleNotifications,
              activeColor: _primaryBlue,
            ),
            onTap: null,
            showDivider: false,
          ),
        ],
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    String? subtitle,
    required Widget trailing,
    required VoidCallback? onTap,
    required bool showDivider,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A237E),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9E9E9E)),
                        ),
                      ],
                    ],
                  ),
                ),
                trailing,
              ],
            ),
          ),
        ),
        if (showDivider)
          const Divider(
            height: 1,
            indent: 68,
            endIndent: 16,
            color: Color(0xFFEEF0F8),
          ),
      ],
    );
  }

  // ── Sign-out button ─────────────────────────────────────────────────────────

  Widget _buildSignOutButton(
      BuildContext context, ProfileViewModel vm) {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed:
            vm.isLoading ? null : () => _handleSignOut(context),
        icon: vm.isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.red),
              )
            : const Icon(Icons.logout_rounded),
        label: const Text(
          'Sign Out',
          style:
              TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red.shade600,
          side: BorderSide(color: Colors.red.shade400, width: 1.5),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
