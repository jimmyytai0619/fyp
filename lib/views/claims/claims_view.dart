import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/claim.dart';
import '../../viewmodels/claims_viewmodel.dart';
import 'chat_view.dart';
import 'handover_view.dart';

class ClaimsView extends StatefulWidget {
  /// Which tab to open on: 0 = My Claims, 1 = Requests.
  final int initialTab;

  const ClaimsView({super.key, this.initialTab = 0});

  @override
  State<ClaimsView> createState() => _ClaimsViewState();
}

class _ClaimsViewState extends State<ClaimsView> {
  static const _primaryBlue = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      context.read<ClaimsViewModel>().fetchAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F4FF),
        appBar: AppBar(
          backgroundColor: _primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text('Claims & Handover',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
            tabs: [
              Tab(text: 'My Claims'),
              Tab(text: 'Requests'),
            ],
          ),
        ),
        body: Consumer<ClaimsViewModel>(
          builder: (context, vm, _) {
            if (vm.isLoading) {
              return const Center(
                  child: CircularProgressIndicator(color: _primaryBlue));
            }
            return RefreshIndicator(
              onRefresh: () => vm.fetchAll(),
              child: TabBarView(
                children: [
                  _ClaimList(claims: vm.myClaims, asFinder: false),
                  _ClaimList(claims: vm.requests, asFinder: true),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ClaimList extends StatelessWidget {
  final List<Claim> claims;
  final bool asFinder;

  const _ClaimList({required this.claims, required this.asFinder});

  @override
  Widget build(BuildContext context) {
    if (claims.isEmpty) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    asFinder
                        ? Icons.inbox_outlined
                        : Icons.shield_outlined,
                    size: 56,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    asFinder
                        ? 'No one has claimed your found items yet.'
                        : "You haven't claimed any items yet.",
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: claims.length,
      itemBuilder: (_, i) =>
          _ClaimCard(claim: claims[i], asFinder: asFinder),
    );
  }
}

class _ClaimCard extends StatelessWidget {
  final Claim claim;
  final bool asFinder;

  const _ClaimCard({required this.claim, required this.asFinder});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: claim.itemImageUrl.isNotEmpty
                    ? Image.network(claim.itemImageUrl,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _thumb())
                    : _thumb(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(claim.itemCategory,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A237E))),
                    const SizedBox(height: 4),
                    Text(
                      claim.itemLocation.isNotEmpty
                          ? claim.itemLocation
                          : '—',
                      style: TextStyle(
                          fontSize: 12.5, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    _StatusBadge(status: claim.status),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _actions(context),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context) {
    final vm = context.read<ClaimsViewModel>();

    // Finder, pending request → approve / reject
    if (asFinder && claim.status == 'Pending') {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => vm.reject(claim.id),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFC62828),
                side: const BorderSide(color: Color(0xFFC62828)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Reject'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: () => vm.approve(claim.id),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Approve'),
            ),
          ),
        ],
      );
    }

    // Verified → open chat (both sides); finder can also mark returned
    if (claim.status == 'Verified') {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ChatView(claim: claim, isFinder: asFinder),
                    ),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: const Text('Open Chat'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              if (asFinder) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _markReturnedWithProof(context, vm),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2E7D32),
                      side: const BorderSide(color: Color(0xFF2E7D32)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Mark Returned'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          _handoverAction(context),
        ],
      );
    }

    // Claimant, pending → waiting note
    if (!asFinder && claim.status == 'Pending') {
      return _note('Waiting for the finder to approve your claim.');
    }
    if (claim.status == 'Rejected') {
      return _note('This claim was rejected by the finder.');
    }
    if (claim.status == 'Returned') {
      final hasProof = (claim.returnEvidenceUrl ?? '').isNotEmpty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _note('Item returned. Claim complete. 🎉'),
          if (hasProof) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.verified_outlined,
                    size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text('Handover proof',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => _showProof(context, claim.returnEvidenceUrl!),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  claim.returnEvidenceUrl!,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _thumb(),
                ),
              ),
            ),
          ],
        ],
      );
    }
    return const SizedBox.shrink();
  }

  /// Secure-handover row on a verified claim: the finder shows a QR/code, the
  /// claimant scans/enters it, and once done both see a "verified" badge.
  Widget _handoverAction(BuildContext context) {
    if (claim.handoverVerified) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified_user_rounded,
                size: 16, color: Color(0xFF2E7D32)),
            SizedBox(width: 6),
            Text('Handover verified',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2E7D32))),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () async {
          if (asFinder) {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => HandoverCodeView(claim: claim)));
          } else {
            final ok = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                    builder: (_) => HandoverVerifyView(claim: claim)));
            if (ok == true && context.mounted) {
              context.read<ClaimsViewModel>().fetchAll();
            }
          }
        },
        icon: Icon(asFinder ? Icons.qr_code_2_rounded : Icons.qr_code_scanner_rounded,
            size: 18),
        label: Text(asFinder ? 'Show Handover Code' : 'Verify Handover'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF1565C0),
          side: const BorderSide(color: Color(0xFF1565C0)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  /// Finder marks the item returned — but must first attach a proof photo of the
  /// handover (evidence for security). No photo → no return.
  Future<void> _markReturnedWithProof(
      BuildContext context, ClaimsViewModel vm) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Add handover proof',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Take a photo of the item being handed over as evidence.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Color(0xFF757575)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded,
                  color: Color(0xFF2E7D32)),
              title: const Text('Take a Photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: Color(0xFF1565C0)),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;

    XFile? picked;
    try {
      picked = await ImagePicker()
          .pickImage(source: source, imageQuality: 70, maxWidth: 1280);
    } catch (_) {
      picked = null;
    }
    if (picked == null || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final ok = await vm.markReturned(claim, File(picked.path));
    if (!context.mounted) return;
    Navigator.of(context).pop(); // close the loader

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Item marked as returned with proof.'
            : 'Could not mark returned. Please try again.'),
        backgroundColor:
            ok ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Opens the proof photo full-screen.
  void _showProof(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: InteractiveViewer(
            child: Image.network(url, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Widget _note(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
      );

  Widget _thumb() => Container(
        width: 64,
        height: 64,
        color: const Color(0xFFE8EAF6),
        child: const Icon(Icons.image_outlined, color: Color(0xFF9FA8DA)),
      );
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'Verified' => (const Color(0xFFE3F2FD), const Color(0xFF1565C0)),
      'Returned' => (const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
      'Rejected' => (const Color(0xFFFFEBEE), const Color(0xFFC62828)),
      _ => (const Color(0xFFFFF8E1), const Color(0xFFE65100)), // Pending/Quiz
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status,
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}
