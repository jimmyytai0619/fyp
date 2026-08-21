import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/item_report.dart';
import '../../viewmodels/manage_records_viewmodel.dart';
import '../report_item/report_item_view.dart';
import 'record_detail_view.dart';

class ManageRecordsView extends StatefulWidget {
  const ManageRecordsView({super.key});

  @override
  State<ManageRecordsView> createState() => _ManageRecordsViewState();
}

class _ManageRecordsViewState extends State<ManageRecordsView> {
  static const _primaryBlue = Color(0xFF1565C0);
  static const _bgColor = Color(0xFFF0F4FF);

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      context.read<ManageRecordsViewModel>().fetchMyRecords();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _bgColor,
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: _primaryBlue,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Report Lost Item',
              style: TextStyle(fontWeight: FontWeight.w700)),
          onPressed: () async {
            final created = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => const ReportItemView(isLost: true),
              ),
            );
            if (created == true && context.mounted) {
              context.read<ManageRecordsViewModel>().fetchMyRecords();
            }
          },
        ),
        appBar: AppBar(
          backgroundColor: _primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Manage My Records',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            tabs: [
              Tab(text: 'My Lost Items'),
              Tab(text: 'My Found Items'),
            ],
          ),
        ),
        body: Column(
          children: [
            _RecordSearchBar(primaryColor: _primaryBlue),
            Expanded(
              child: Consumer<ManageRecordsViewModel>(
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

            return TabBarView(
              children: [
                _ItemList(
                  items: vm.filteredLostItems,
                  isLost: true,
                  emptyIcon: Icons.search_off_rounded,
                  emptyMessage: "You haven't reported any lost items yet.",
                  accentColor: _primaryBlue,
                ),
                _ItemList(
                  items: vm.filteredFoundItems,
                  isLost: false,
                  claimStatuses: vm.foundClaimStatuses,
                  emptyIcon: Icons.inventory_2_outlined,
                  emptyMessage: "You haven't reported any found items yet.",
                  accentColor: const Color(0xFF00897B),
                ),
              ],
            );
          },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Search bar ────────────────────────────────────────────────────────────────

class _RecordSearchBar extends StatefulWidget {
  final Color primaryColor;
  const _RecordSearchBar({required this.primaryColor});

  @override
  State<_RecordSearchBar> createState() => _RecordSearchBarState();
}

class _RecordSearchBarState extends State<_RecordSearchBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: TextField(
        controller: _controller,
        onChanged: (v) =>
            context.read<ManageRecordsViewModel>().setSearchQuery(v),
        decoration: InputDecoration(
          hintText: 'Search my records (category, location…)',
          hintStyle: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 14),
          prefixIcon:
              Icon(Icons.search_rounded, color: widget.primaryColor, size: 22),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () {
                    _controller.clear();
                    context.read<ManageRecordsViewModel>().setSearchQuery('');
                    setState(() {});
                  },
                ),
          filled: true,
          fillColor: const Color(0xFFF8FAFF),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
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
            borderSide: BorderSide(color: widget.primaryColor, width: 1.6),
          ),
        ),
      ),
    );
  }
}

// ── Item List ─────────────────────────────────────────────────────────────────

class _ItemList extends StatelessWidget {
  final List<ItemReport> items;
  final bool isLost;
  final IconData emptyIcon;
  final String emptyMessage;
  final Color accentColor;
  final Map<String, String>? claimStatuses;

  const _ItemList({
    required this.items,
    required this.isLost,
    required this.emptyIcon,
    required this.emptyMessage,
    required this.accentColor,
    this.claimStatuses,
  });

  void _openDetail(BuildContext context, ItemReport item) {
    final vm = context.read<ManageRecordsViewModel>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: vm,
          child: RecordDetailView(
            item: item,
            isLost: isLost,
            claimStatus: claimStatuses?[item.id],
          ),
        ),
      ),
    );
  }

  Future<void> _refresh(BuildContext context) =>
      context.read<ManageRecordsViewModel>().fetchMyRecords();

  Future<bool> _confirmDelete(BuildContext context, ItemReport item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete record?'),
        content: Text(
          'This will permanently remove your "${item.category}" '
          '${isLost ? 'lost' : 'found'} report.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF757575))),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete',
                style: TextStyle(
                    color: Color(0xFFD32F2F), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return false;

    try {
      await context
          .read<ManageRecordsViewModel>()
          .deleteRecord(id: item.id, isLost: isLost);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Record deleted.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: const Color(0xFFB00020),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  /// Closes a report (lost → resolved, found → returned) or re-opens a closed
  /// one. Keeps the card in place, just updates its state/badge.
  Future<void> _resolveItem(BuildContext context, ItemReport item) async {
    final reopen = item.isClosed;
    try {
      await context
          .read<ManageRecordsViewModel>()
          .resolveRecord(id: item.id, isLost: isLost, reopen: reopen);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(reopen
                ? 'Report reopened.'
                : (isLost
                    ? 'Lost report marked resolved.'
                    : 'Item marked returned.')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: const Color(0xFFB00020),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      // Wrap in a scrollable so pull-to-refresh still works when empty.
      return RefreshIndicator(
        onRefresh: () => _refresh(context),
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: _EmptyState(
                  icon: emptyIcon, message: emptyMessage, color: accentColor),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _refresh(context),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[i];
          return Dismissible(
            key: ValueKey(item.id),
            direction: DismissDirection.horizontal,
            confirmDismiss: (dir) async {
              if (dir == DismissDirection.endToStart) {
                return _confirmDelete(context, item); // swipe left = delete
              }
              await _resolveItem(context, item); // swipe right = resolve/reopen
              return false; // keep the card in place
            },
            background: Container(
              // swipe right → mark resolved (or reopen if already closed)
              alignment: Alignment.centerLeft,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.only(left: 24),
              decoration: BoxDecoration(
                color: item.isClosed
                    ? const Color(0xFF757575)
                    : const Color(0xFF2E7D32),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                  item.isClosed
                      ? Icons.undo_rounded
                      : Icons.check_circle_outline_rounded,
                  color: Colors.white,
                  size: 26),
            ),
            secondaryBackground: Container(
              // swipe left → delete
              alignment: Alignment.centerRight,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.only(right: 24),
              decoration: BoxDecoration(
                color: const Color(0xFFD32F2F),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  color: Colors.white, size: 26),
            ),
            child: GestureDetector(
              onTap: () => _openDetail(context, item),
              child: _RecordCard(
                item: item,
                accentColor: accentColor,
                claimStatus: claimStatuses?[item.id],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Claim status badge (found items with claim activity) ──────────────────────

class _ClaimBadge extends StatelessWidget {
  final String status;
  const _ClaimBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'Verified' => (const Color(0xFFE3F2FD), const Color(0xFF1565C0)),
      'Returned' => (const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
      'Rejected' => (const Color(0xFFFFEBEE), const Color(0xFFC62828)),
      _ => (const Color(0xFFFFF8E1), const Color(0xFFE65100)),
    };
    final label = status == 'Pending' ? 'Claim pending' : status;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_user_rounded, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }
}

// ── Record Card ───────────────────────────────────────────────────────────────

class _RecordCard extends StatelessWidget {
  final ItemReport item;
  final Color accentColor;
  final String? claimStatus;

  const _RecordCard(
      {required this.item, required this.accentColor, this.claimStatus});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(16)),
            child: item.imageUrl.isNotEmpty
                ? Image.network(
                    item.imageUrl,
                    width: 90,
                    height: 90,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, st) => _placeholderThumb(accentColor),
                  )
                : _placeholderThumb(accentColor),
          ),
          // Details
          Expanded(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.category,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 13, color: Colors.grey.shade500),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          item.locationFound.isNotEmpty
                              ? item.locationFound
                              : '—',
                          style: TextStyle(
                              fontSize: 12.5, color: Colors.grey.shade600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (item.isClosed)
                        _closedBadge()
                      else if (claimStatus != null)
                        _ClaimBadge(status: claimStatus!)
                      else
                        _StatusBadge(status: item.status),
                      Text(
                        _formatDate(item.createdAt),
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _closedBadge() {
    final label = item.isResolved ? 'Resolved' : 'Returned';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 12, color: Color(0xFF2E7D32)),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2E7D32))),
        ],
      ),
    );
  }

  Widget _placeholderThumb(Color color) {
    return Container(
      width: 90,
      height: 90,
      color: color.withValues(alpha: 0.08),
      child: Icon(Icons.image_outlined, color: color.withValues(alpha: 0.4),
          size: 32),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ── Status Badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status.toLowerCase()) {
      'resolved' => (const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
      'active' => (const Color(0xFFE3F2FD), const Color(0xFF1565C0)),
      _ => (const Color(0xFFFFF8E1), const Color(0xFFE65100)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;

  const _EmptyState(
      {required this.icon, required this.message, required this.color});

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
                color: color.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 42, color: color.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
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
