import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/item_report.dart';
import '../../viewmodels/manage_records_viewmodel.dart';

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
        body: Consumer<ManageRecordsViewModel>(
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
                  items: vm.myLostItems,
                  emptyIcon: Icons.search_off_rounded,
                  emptyMessage: "You haven't reported any lost items yet.",
                  accentColor: _primaryBlue,
                ),
                _ItemList(
                  items: vm.myFoundItems,
                  emptyIcon: Icons.inventory_2_outlined,
                  emptyMessage: "You haven't reported any found items yet.",
                  accentColor: const Color(0xFF00897B),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Item List ─────────────────────────────────────────────────────────────────

class _ItemList extends StatelessWidget {
  final List<ItemReport> items;
  final IconData emptyIcon;
  final String emptyMessage;
  final Color accentColor;

  const _ItemList({
    required this.items,
    required this.emptyIcon,
    required this.emptyMessage,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyState(icon: emptyIcon, message: emptyMessage,
          color: accentColor);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: items.length,
      itemBuilder: (_, i) =>
          _RecordCard(item: items[i], accentColor: accentColor),
    );
  }
}

// ── Record Card ───────────────────────────────────────────────────────────────

class _RecordCard extends StatelessWidget {
  final ItemReport item;
  final Color accentColor;

  const _RecordCard({required this.item, required this.accentColor});

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
