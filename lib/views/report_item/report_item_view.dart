import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

import '../../viewmodels/report_item_viewmodel.dart';

class ReportItemView extends StatefulWidget {
  const ReportItemView({super.key});

  @override
  State<ReportItemView> createState() => _ReportItemViewState();
}

class _ReportItemViewState extends State<ReportItemView> {
  final _formKey = GlobalKey<FormState>();
  final _locationCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();

  static const _categories = [
    'Electronics',
    'IDs & Cards',
    'Bags & Wallets',
    'Other',
  ];
  String _selectedCategory = 'Electronics';

  static const _primaryBlue = Color(0xFF1565C0);
  static const _teal = Color(0xFF00897B);

  @override
  void dispose() {
    _locationCtrl.dispose();
    _descCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  // ── Image picker sheet ────────────────────────────────────────────────────

  void _showImageSourceSheet(ReportItemViewModel vm) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select Image Source',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE3F2FD),
                child: Icon(Icons.camera_alt_rounded, color: _primaryBlue),
              ),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                vm.pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F5E9),
                child: Icon(Icons.photo_library_rounded, color: _teal),
              ),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                vm.pickImage(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit(ReportItemViewModel vm) async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    try {
      await vm.submitReport(
        category: _selectedCategory,
        location: _locationCtrl.text,
        description: _descCtrl.text,
        tags: _tagsCtrl.text,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(_snackbar(
        'Item added to database!',
        isError: false,
      ));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(_snackbar(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      ));
    }
  }

  SnackBar _snackbar(String msg, {required bool isError}) => SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
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
      );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ReportItemViewModel(),
      child: Consumer<ReportItemViewModel>(
        builder: (context, vm, _) => Stack(
          children: [
            Scaffold(
              backgroundColor: const Color(0xFFF0F4FF),
              appBar: AppBar(
                backgroundColor: _primaryBlue,
                foregroundColor: Colors.white,
                title: const Text(
                  'Report Found Item',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                elevation: 0,
              ),
              body: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _imageSection(vm),
                    const SizedBox(height: 24),
                    _formCard(vm),
                    const SizedBox(height: 24),
                    _submitButton(vm),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
            if (vm.isLoading)
              Container(
                color: Colors.black.withValues(alpha: 0.45),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Image section ─────────────────────────────────────────────────────────

  Widget _imageSection(ReportItemViewModel vm) {
    return GestureDetector(
      onTap: () => _showImageSourceSheet(vm),
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: vm.selectedImage == null
                ? _primaryBlue.withValues(alpha: 0.3)
                : _teal,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: vm.selectedImage == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: _primaryBlue.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add_a_photo_rounded,
                        color: _primaryBlue, size: 32),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Tap to Take Photo or Upload',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: _primaryBlue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Camera or Gallery',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(vm.selectedImage!, fit: BoxFit.cover),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: vm.clearImage,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ── Form card ─────────────────────────────────────────────────────────────

  Widget _formCard(ReportItemViewModel vm) {
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
          _label('Category'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedCategory,
            decoration: _inputDeco(
                hint: 'Select category', icon: Icons.category_outlined),
            items: _categories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _selectedCategory = v);
            },
          ),
          const SizedBox(height: 20),
          _label('Specific Location Found *'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _locationCtrl,
            textInputAction: TextInputAction.next,
            decoration: _inputDeco(
                hint: 'e.g. Library 2nd floor, near the printer',
                icon: Icons.location_on_outlined),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Location is required.' : null,
          ),
          const SizedBox(height: 20),
          _label('Notes / Description'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _descCtrl,
            maxLines: 3,
            textInputAction: TextInputAction.next,
            decoration: _inputDeco(
                hint: 'Any distinguishing features, colour, brand…',
                icon: Icons.notes_rounded),
          ),
          const SizedBox(height: 20),
          _label('Tags (comma separated)'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _tagsCtrl,
            textInputAction: TextInputAction.done,
            decoration: _inputDeco(
                hint: 'e.g. blue, samsung, charger',
                icon: Icons.label_outline_rounded),
          ),
        ],
      ),
    );
  }

  // ── Submit button ─────────────────────────────────────────────────────────

  Widget _submitButton(ReportItemViewModel vm) {
    return SizedBox(
      height: 54,
      child: ElevatedButton.icon(
        onPressed: vm.isLoading ? null : () => _submit(vm),
        icon: const Icon(Icons.cloud_upload_rounded),
        label: const Text(
          'Upload & Process Image',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _teal,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _teal.withValues(alpha: 0.5),
          elevation: 3,
          shadowColor: _teal.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF37474F),
        ),
      );

  InputDecoration _inputDeco({required String hint, required IconData icon}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 14),
        prefixIcon: Icon(icon, color: const Color(0xFF9E9E9E), size: 20),
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
          borderSide: const BorderSide(color: _primaryBlue, width: 1.8),
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
