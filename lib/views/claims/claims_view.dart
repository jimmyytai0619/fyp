import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/claim.dart';
import '../../viewmodels/claims_viewmodel.dart';
import 'chat_view.dart';

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
      return Row(
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
                onPressed: () => vm.markReturned(claim),
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
      return _note('Item returned. Claim complete. 🎉');
    }
    return const SizedBox.shrink();
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
