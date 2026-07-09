import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/item_report.dart';
import '../../viewmodels/manage_records_viewmodel.dart';

/// Detail + edit + delete for one of the user's own records.
class RecordDetailView extends StatelessWidget {
  final ItemReport item;
  final bool isLost;
  final String? claimStatus; // found items only

  const RecordDetailView({
    super.key,
    required this.item,
    required this.isLost,
    this.claimStatus,
  });

  static const _primaryBlue = Color(0xFF1565C0);
  static const _categories = [
    'Electronics',
    'IDs & Cards',
    'Bags & Wallets',
    'Keys & Lanyards',
    'Books & Stationery',
    'Clothing & Accessories',
    'Other',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        title: const Text('Record Details',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => _showEditSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (item.imageUrl.isNotEmpty)
              Image.network(item.imageUrl,
                  height: 240,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                        height: 240,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image_outlined,
                            size: 56, color: Colors.grey),
                      )),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _pill(isLost ? 'Lost' : 'Found',
                          isLost ? _primaryBlue : const Color(0xFF00897B)),
                      if (!isLost && claimStatus != null) ...[
                        const SizedBox(width: 8),
                        _claimPill(claimStatus!),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),
                  _detailCard([
                    _row(Icons.category_outlined, 'Category', item.category),
                    const Divider(height: 24),
                    _row(Icons.location_on_outlined, 'Location',
                        item.locationFound.isNotEmpty ? item.locationFound : '—'),
                    const Divider(height: 24),
                    _row(Icons.notes_rounded, 'Description',
                        item.description.isNotEmpty ? item.description : '—'),
                    const Divider(height: 24),
                    _row(Icons.calendar_today_outlined, 'Reported On',
                        _formatDate(item.createdAt)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Edit ────────────────────────────────────────────────────────────────────

  void _showEditSheet(BuildContext context) {
    final vm = context.read<ManageRecordsViewModel>();
    final locationCtrl = TextEditingController(text: item.locationFound);
    final descCtrl = TextEditingController(text: item.description);
    String category =
        _categories.contains(item.category) ? item.category : 'Other';
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (sheetCtx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Edit Record',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: category,
                decoration: _deco('Category', Icons.category_outlined),
                items: _categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setSheet(() => category = v ?? category),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: locationCtrl,
                decoration: _deco('Location', Icons.location_on_outlined),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: _deco('Description', Icons.notes_rounded),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setSheet(() => saving = true);
                          try {
                            await vm.updateRecord(
                              id: item.id,
                              isLost: isLost,
                              category: category,
                              location: locationCtrl.text.trim(),
                              description: descCtrl.text.trim(),
                            );
                            if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                            if (context.mounted) Navigator.of(context).pop();
                          } catch (e) {
                            setSheet(() => saving = false);
                            if (sheetCtx.mounted) {
                              ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                SnackBar(
                                    content: Text(e
                                        .toString()
                                        .replaceFirst('Exception: ', ''))),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Save Changes',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Delete ──────────────────────────────────────────────────────────────────

  Future<void> _confirmDelete(BuildContext context) async {
    final vm = context.read<ManageRecordsViewModel>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete record?'),
        content: Text(
            'This permanently removes your "${item.category}" ${isLost ? 'lost' : 'found'} report.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel',
                  style: TextStyle(color: Color(0xFF757575)))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete',
                  style: TextStyle(
                      color: Color(0xFFD32F2F), fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await vm.deleteRecord(id: item.id, isLost: isLost);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  // ── UI helpers ──────────────────────────────────────────────────────────────

  InputDecoration _deco(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: const Color(0xFFF8FAFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDDE3F0)),
        ),
      );

  Widget _detailCard(List<Widget> children) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _row(IconData icon, String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: _primaryBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9E9E9E),
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A237E))),
              ],
            ),
          ),
        ],
      );

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12)),
      );

  Widget _claimPill(String status) {
    final (bg, fg) = switch (status) {
      'Verified' => (const Color(0xFFE3F2FD), const Color(0xFF1565C0)),
      'Returned' => (const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
      'Rejected' => (const Color(0xFFFFEBEE), const Color(0xFFC62828)),
      _ => (const Color(0xFFFFF8E1), const Color(0xFFE65100)),
    };
    final label = status == 'Pending' ? 'Claim pending' : status;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}
