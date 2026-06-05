import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/edit_profile_viewmodel.dart';

/// Entry point — wraps the screen in its own scoped [EditProfileViewModel].
class EditProfileView extends StatelessWidget {
  const EditProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => EditProfileViewModel(),
      child: const _EditProfileScaffold(),
    );
  }
}

// ── Scaffold ──────────────────────────────────────────────────────────────────

class _EditProfileScaffold extends StatefulWidget {
  const _EditProfileScaffold();

  @override
  State<_EditProfileScaffold> createState() => _EditProfileScaffoldState();
}

class _EditProfileScaffoldState extends State<_EditProfileScaffold> {
  // ── Constants ──────────────────────────────────────────────────────────────

  static const _primaryBlue = Color(0xFF1565C0);
  static const _bgColor = Color(0xFFF0F4FF);

  // ── Controllers & form key ─────────────────────────────────────────────────

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _controllersInitialised = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final vm = context.read<EditProfileViewModel>();
      await vm.loadUserData();
      if (!mounted) return;
      // Populate controllers exactly once after data arrives.
      if (!_controllersInitialised) {
        _nameCtrl.text = vm.initialName ?? '';
        _phoneCtrl.text = vm.initialPhone ?? '';
        _controllersInitialised = true;
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final vm = context.read<EditProfileViewModel>();
    try {
      await vm.updateProfile(
        newName: _nameCtrl.text,
        newPhone: _phoneCtrl.text,
      );
      if (!mounted) return;
      _showSnackbar('Profile updated successfully!', isError: false);
      // Pop with `true` so ProfileView knows to refresh its data.
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showSnackbar(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  // ── Snackbar helper ────────────────────────────────────────────────────────

  void _showSnackbar(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor:
            isError ? const Color(0xFFD32F2F) : const Color(0xFF2E7D32),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<EditProfileViewModel>(
      builder: (context, vm, _) {
        // Full-screen loader on initial data fetch.
        if (vm.isLoading && !_controllersInitialised) {
          return const Scaffold(
            backgroundColor: _bgColor,
            appBar: _StyledAppBar(),
            body: Center(
              child: CircularProgressIndicator(color: _primaryBlue),
            ),
          );
        }

        return Stack(
          children: [
            Scaffold(
              backgroundColor: _bgColor,
              appBar: const _StyledAppBar(),
              body: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const SizedBox(height: 4),
                    _buildAvatarBanner(vm),
                    const SizedBox(height: 28),
                    _buildFormCard(vm),
                    const SizedBox(height: 28),
                    _buildSaveButton(vm),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // Translucent save-in-progress overlay.
            if (vm.isLoading && _controllersInitialised)
              Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
          ],
        );
      },
    );
  }

  // ── Avatar banner ──────────────────────────────────────────────────────────

  Widget _buildAvatarBanner(EditProfileViewModel vm) {
    // Derive initials from whatever is currently in the name controller.
    String initials() {
      final text = _nameCtrl.text.trim();
      if (text.isEmpty) return '?';
      final parts = text.split(RegExp(r'\s+'));
      if (parts.length == 1) return parts[0][0].toUpperCase();
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }

    return Center(
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: _primaryBlue.withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: AnimatedBuilder(
                animation: _nameCtrl,
                builder: (_, __) => Text(
                  initials(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            vm.studentId ?? '',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF607D8B),
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  // ── Form card ──────────────────────────────────────────────────────────────

  Widget _buildFormCard(EditProfileViewModel vm) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Full Name ──────────────────────────────────────────────────────
          _fieldLabel('Full Name'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _nameCtrl,
            enabled: !vm.isLoading,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: _inputDeco(
              hint: 'Enter your full name',
              icon: Icons.person_outline_rounded,
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Full name is required.';
              }
              if (v.trim().length < 2) {
                return 'Name must be at least 2 characters.';
              }
              return null;
            },
          ),

          const SizedBox(height: 22),

          // ── Phone Number ───────────────────────────────────────────────────
          _fieldLabel('Phone Number'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _phoneCtrl,
            enabled: !vm.isLoading,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            decoration: _inputDeco(
              hint: 'e.g. 0123456789',
              icon: Icons.phone_outlined,
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null; // optional
              final digits = v.replaceAll(RegExp(r'\D'), '');
              if (digits.length < 9 || digits.length > 15) {
                return 'Enter a valid phone number.';
              }
              return null;
            },
          ),

          const SizedBox(height: 22),

          // ── Student ID (read-only) ─────────────────────────────────────────
          _fieldLabel('Student ID'),
          const SizedBox(height: 4),
          _readOnlyNote('Student ID cannot be changed after registration.'),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: vm.studentId ?? 'Not set',
            readOnly: true,
            enabled: false,
            decoration: _inputDeco(
              hint: '',
              icon: Icons.badge_outlined,
            ).copyWith(
              // Soften the disabled colour so it reads clearly but still
              // signals "locked".
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE0E6F0)),
              ),
              fillColor: const Color(0xFFF3F5FA),
            ),
            style: const TextStyle(
              color: Color(0xFF90A4AE),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Save button ────────────────────────────────────────────────────────────

  Widget _buildSaveButton(EditProfileViewModel vm) {
    return SizedBox(
      height: 54,
      child: ElevatedButton.icon(
        onPressed: vm.isLoading ? null : _submit,
        icon: const Icon(Icons.save_rounded),
        label: const Text(
          'Save Changes',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _primaryBlue.withValues(alpha: 0.5),
          elevation: 3,
          shadowColor: _primaryBlue.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _fieldLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF37474F),
        ),
      );

  Widget _readOnlyNote(String text) => Row(
        children: [
          const Icon(Icons.lock_outline_rounded,
              size: 13, color: Color(0xFFB0BEC5)),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFFB0BEC5),
            ),
          ),
        ],
      );

  InputDecoration _inputDeco({
    required String hint,
    required IconData icon,
  }) =>
      InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: Color(0xFFBDBDBD), fontSize: 14),
        prefixIcon:
            Icon(icon, color: const Color(0xFF9E9E9E), size: 20),
        filled: true,
        fillColor: const Color(0xFFF8FAFF),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDDE3F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDDE3F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: _primaryBlue, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD32F2F)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFFD32F2F), width: 1.8),
        ),
      );
}

// ── Shared AppBar ─────────────────────────────────────────────────────────────

class _StyledAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _StyledAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: const Color(0xFF1565C0),
      foregroundColor: Colors.white,
      title: const Text(
        'Edit Profile',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: () => Navigator.of(context).pop(false),
      ),
    );
  }
}
