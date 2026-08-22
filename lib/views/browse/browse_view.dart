import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/item_report.dart';
import '../../models/match_result.dart';
import '../../viewmodels/browse_viewmodel.dart';
import '../search/item_detail_view.dart';

class BrowseView extends StatefulWidget {
  const BrowseView({super.key});

  @override
  State<BrowseView> createState() => _BrowseViewState();
}

class _BrowseViewState extends State<BrowseView> {
  static const _primaryBlue = Color(0xFF1565C0);
  static const _orange = Color(0xFFE65100);
  static const _bgColor = Color(0xFFF0F4FF);

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      context.read<BrowseViewModel>().fetchItems();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Browse Found Items',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: Column(
        children: [
          _SearchBar(primaryColor: _primaryBlue),
          _CategoryFilterBar(primaryColor: _primaryBlue),
          Expanded(
            child: Consumer<BrowseViewModel>(
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
                                  style:
                                      const TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      ),
                    );
                  });
                }

                final items = vm.filteredItems;
                if (items.isEmpty) {
                  return _EmptyState(color: _orange);
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _ItemCard(item: items[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Smart Text Search Bar (FR 4.1) ───────────────────────────────────────────

class _SearchBar extends StatefulWidget {
  final Color primaryColor;

  const _SearchBar({required this.primaryColor});

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    context.read<BrowseViewModel>().setSearchQuery(_controller.text);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: 'Search by keyword (e.g. wallet, samsung)',
          hintStyle: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 14),
          prefixIcon:
              Icon(Icons.search_rounded, color: widget.primaryColor, size: 22),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () {
                    _controller.clear();
                    context.read<BrowseViewModel>().setSearchQuery('');
                    FocusScope.of(context).unfocus();
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
        onChanged: (_) => setState(() {}), // toggle the clear button
      ),
    );
  }
}

// ── Category Filter Bar ───────────────────────────────────────────────────────

class _CategoryFilterBar extends StatelessWidget {
  final Color primaryColor;

  const _CategoryFilterBar({required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    return Consumer<BrowseViewModel>(
      builder: (context, vm, _) {
        return Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: vm.categories.map((cat) {
                    final isSelected = vm.selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(cat),
                        selected: isSelected,
                        onSelected: (_) => vm.setCategory(cat),
                        selectedColor: primaryColor,
                        backgroundColor: const Color(0xFFF0F4FF),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF37474F),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSelected
                                ? primaryColor
                                : Colors.grey.shade300,
                          ),
                        ),
                        showCheckmark: false,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),
              // Building + date filters (applied over the loaded results).
              Row(
                children: [
                  Expanded(
                    child: _FilterDropdown(
                      icon: Icons.apartment_rounded,
                      value: vm.selectedBuilding,
                      items: vm.buildings,
                      onChanged: (v) => vm.setBuilding(v ?? 'All'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _FilterDropdown(
                      icon: Icons.event_rounded,
                      value: _dateLabel(vm.maxAgeDays),
                      items: const ['Any time', 'Last 7 days', 'Last 30 days'],
                      onChanged: (v) => vm.setMaxAgeDays(_dateDays(v)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

String _dateLabel(int days) => switch (days) {
      7 => 'Last 7 days',
      30 => 'Last 30 days',
      _ => 'Any time',
    };

int _dateDays(String? label) => switch (label) {
      'Last 7 days' => 7,
      'Last 30 days' => 30,
      _ => 0,
    };

// ── Compact filter dropdown (building / date) ────────────────────────────────

class _FilterDropdown extends StatelessWidget {
  final IconData icon;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _FilterDropdown({
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Guard: the building list can change on refetch — fall back to the first.
    final safeValue = items.contains(value) ? value : items.first;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: safeValue,
                items: items
                    .map((e) => DropdownMenuItem(
                          value: e,
                          child: Text(e,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13)),
                        ))
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Item Card ─────────────────────────────────────────────────────────────────

class _ItemCard extends StatelessWidget {
  final ItemReport item;

  const _ItemCard({required this.item});

  void _openDetail(BuildContext context) {
    // Browse uses ItemReport; the detail/claim screen takes a MatchResult.
    // No AI score here, so confidenceScore is 0 (the badge is hidden for it).
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openDetail(context),
      child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail
          Expanded(
            child: item.imageUrl.isNotEmpty
                ? Image.network(
                    item.imageUrl,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, st) => _placeholder(),
                  )
                : _placeholder(),
          ),
          // Details
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A237E),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined,
                        size: 12, color: Colors.grey.shade500),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        item.locationFound.isNotEmpty
                            ? item.locationFound
                            : '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFFE8EAF6),
      child: const Center(
        child: Icon(Icons.image_outlined,
            size: 36, color: Color(0xFF9FA8DA)),
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final Color color;

  const _EmptyState({required this.color});

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
              child: Icon(Icons.inventory_2_outlined,
                  size: 42, color: color.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 20),
            const Text(
              'No items found in this category.',
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
