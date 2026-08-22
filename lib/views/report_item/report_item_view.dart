import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/classification_service.dart';
import '../../viewmodels/manage_records_viewmodel.dart';
import '../../viewmodels/report_item_viewmodel.dart';
import '../manage_records/manage_records_view.dart';

class ReportItemView extends StatefulWidget {
  /// When true, the screen reports a LOST item; otherwise a FOUND item.
  final bool isLost;

  const ReportItemView({super.key, this.isLost = false});

  @override
  State<ReportItemView> createState() => _ReportItemViewState();
}

class _ReportItemViewState extends State<ReportItemView> {
  final _formKey = GlobalKey<FormState>();
  final _locationCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _questionCtrl = TextEditingController();
  final _answerCtrl = TextEditingController();

  static const _categories = ClassificationService.categories;
  String? _selectedCategory;

  // ── Category-specific ownership questions (FR 5.2) ──────────────────────────
  static const _customQuestion = '__custom__';
  String? _selectedQuestion;

  static const Map<String, List<String>> _questionsByCategory = {
    'Electronics': [
      'What brand is it?',
      'What is on the lock screen / wallpaper?',
      'What colour is the casing?',
      'What model is it?',
    ],
    'Water Bottles': [
      'What brand is it?',
      'What colour is it?',
      'What size / capacity is it?',
      'Any stickers, dents or marks on it?',
    ],
    'IDs & Cards': [
      'What is the full name on the card?',
      'What is the ID / matric number?',
      'Which bank or institution issued it?',
    ],
    'Bags & Wallets': [
      'What colour is it?',
      'What brand is it?',
      'Name one item inside it.',
    ],
    'Keys & Lanyards': [
      'How many keys are attached?',
      'What colour is the lanyard?',
      'Describe the keychain or charm.',
    ],
    'Books & Stationery': [
      'What is the title or subject?',
      'Whose name is written inside?',
      'What colour is the cover?',
    ],
    'Clothing & Accessories': [
      'What brand is it?',
      'What size is it?',
      'What colour is it?',
    ],
    'Other': ['Describe a unique feature of the item.', 'What colour is it?'],
  };

  List<String> get _currentQuestions =>
      _questionsByCategory[_selectedCategory ?? 'Other'] ??
      _questionsByCategory['Other']!;

  // ── Cascading location (Building → specific spot) ───────────────────────────
  static const _otherSpot = 'Other (specify)';
  String? _selectedArea;
  String? _selectedSpot;

  static const List<String> _areas = [
    // ── Major Buildings ──
    'Arena (TA)',
    'Tun Tan Siew Sin Building (Administration)',
    'Tan Sri Khaw Kai Boh Building',
    'Cyber Centre',
    'University College Hall (UC Hall)',
    'Main Library',
    'Postgraduate Library',
    'Sports Complex',
    'CPE Centre',
    'VTAR Institute',
    'Student Hostel',
    'CECE Kindergarten',
    // ── Academic Blocks ──
    'Block A', 'Block B', 'Block C', 'Block D', 'Block E', 'Block G',
    'Block H', 'Block K', 'Block L', 'Block M', 'Block N', 'Block P',
    'Block PA', 'Block Q', 'Block R', 'Block S', 'Block SA', 'Block SB',
    'Block SC', 'Block SD', 'Block SE', 'Block SF', 'Block V', 'Block W',
    'Block X', 'Block Y', 'Block AA', 'Block AB', 'Block CC',
    // ── Lecture Theatres (DK) ──
    'DK A', 'DK B', 'DK C', 'DK D', 'DK E',
    'DK 1', 'DK 2', 'DK 3', 'DK 4', 'DK 5', 'DK 6', 'DK 7', 'DK 8',
    'DK W', 'DK X', 'DK Y', 'DK Z',
    'DK ABA', 'DK ABB', 'DK ABC', 'DK ABD', 'DK ABE', 'DK ABF',
    // ── Food & Student Facilities ──
    'The Red Bricks Cafeteria',
    'Yum Yum Park / Cafeteria',
    'The Roofs',
    'Training Restaurant',
    'Student Centre (within Arena)',
    'Clubhouse',
    // ── Sports & Outdoor Facilities ──
    'Football Field',
    'Swimming Pool',
    'Basketball Courts',
    'Volleyball Court',
    'Futsal Court',
    'Tennis Courts',
    'Multi-purpose Courts',
    // ── Other Facilities ──
    'Workshops',
    'Fern House',
    'East Campus',
    'Car Park',
    'Guard House / Campus Gate',
    'Other',
  ];

  // Generic spots used for any building without a custom list below (covers the
  // academic blocks and DK lecture theatres, which are the common cases).
  static const List<String> _defaultSpots = [
    'Entrance / Lobby',
    'Classroom',
    'Lab',
    'Corridor / Walkway',
    'Toilet',
    'Staircase / Lift',
    _otherSpot,
  ];

  static const Map<String, List<String>> _spotsByArea = {
    'Main Library': [
      'Ground Floor',
      'Level 1',
      'Level 2',
      'Study Area',
      'Help Desk',
      'Discussion Room',
      _otherSpot,
    ],
    'Postgraduate Library': [
      'Reading Area',
      'Study Carrel',
      'Help Desk',
      'Discussion Room',
      _otherSpot,
    ],
    'The Red Bricks Cafeteria': [
      'Seating Area',
      'Food Counter',
      'Entrance',
      _otherSpot,
    ],
    'Yum Yum Park / Cafeteria': [
      'Seating Area',
      'Food Counter',
      'Entrance',
      _otherSpot,
    ],
    'The Roofs': ['Seating Area', 'Food Counter', 'Entrance', _otherSpot],
    'Training Restaurant': ['Dining Area', 'Counter', 'Entrance', _otherSpot],
    'Arena (TA)': [
      'Concourse',
      'Hall',
      'Classroom',
      'Student Centre',
      'Entrance',
      'Toilet',
      _otherSpot,
    ],
    'Sports Complex': ['Court', 'Gym', 'Field', 'Changing Room', _otherSpot],
    'Swimming Pool': [
      'Poolside',
      'Changing Room',
      'Spectator Area',
      _otherSpot,
    ],
    'Football Field': ['Field', 'Spectator Stand', 'Entrance', _otherSpot],
    'Basketball Courts': ['Court', 'Bench / Side', _otherSpot],
    'Tennis Courts': ['Court', 'Bench / Side', _otherSpot],
    'Student Hostel': ['Room', 'Common Area', 'Lobby', 'Corridor', _otherSpot],
    'Car Park': [
      'Open-Air Car Park',
      'Covered Car Park',
      'Motorcycle Bay',
      _otherSpot,
    ],
    'Guard House / Campus Gate': [
      'Guard House',
      'Arena Gate',
      'Main Gate',
      _otherSpot,
    ],
    'Other': [_otherSpot],
  };

  List<String> get _currentSpots =>
      _spotsByArea[_selectedArea] ?? _defaultSpots;

  /// Combines the two dropdowns (and the custom text) into one location string.
  String _composedLocation() {
    if (_selectedArea == null) return _locationCtrl.text.trim();
    final spot = _selectedSpot == _otherSpot
        ? _locationCtrl.text.trim()
        : (_selectedSpot ?? '');
    return spot.isEmpty ? _selectedArea! : '$_selectedArea — $spot';
  }

  /// The final question text to save (a preset or the custom one).
  String _resolvedQuestion() => _selectedQuestion == _customQuestion
      ? _questionCtrl.text.trim()
      : (_selectedQuestion ?? '');

  // Date the item was found (FR 2.5). Defaults to today; user can change.
  DateTime? _dateFound = DateTime.now();

  static const _primaryBlue = Color(0xFF1565C0);
  static const _teal = Color(0xFF00897B);

  @override
  void dispose() {
    _locationCtrl.dispose();
    _descCtrl.dispose();
    _questionCtrl.dispose();
    _answerCtrl.dispose();
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
              onTap: () async {
                Navigator.pop(context);
                await vm.pickImage(ImageSource.camera);
                _applySuggestion(vm);
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F5E9),
                child: Icon(Icons.photo_library_rounded, color: _teal),
              ),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(context);
                await vm.pickImage(ImageSource.gallery);
                _applySuggestion(vm);
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
        isLost: widget.isLost,
        category: _selectedCategory ?? '',
        location: _composedLocation(),
        description: _descCtrl.text,
        tags: '', // tags field removed — kept empty for the existing API/DB
        dateFound: widget.isLost ? null : _dateFound,
        securityQuestion: _resolvedQuestion(),
        securityAnswer: _answerCtrl.text,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        _snackbar(
          widget.isLost
              ? 'Lost item report submitted!'
              : 'Item added to database!',
          isError: false,
        ),
      );

      if (widget.isLost) {
        // Show the user their newly saved lost report in Manage My Records.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider(
              create: (_) => ManageRecordsViewModel(),
              child: const ManageRecordsView(),
            ),
          ),
        );
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        _snackbar(e.toString().replaceFirst('Exception: ', ''), isError: true),
      );
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
    backgroundColor: isError
        ? const Color(0xFFD32F2F)
        : const Color(0xFF2E7D32),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                title: Text(
                  widget.isLost ? 'Report Lost Item' : 'Report Found Item',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                elevation: 0,
              ),
              body: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _imageSection(vm),
                    _aiSuggestionSection(vm),
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

  // ── AI auto-classification (Modules 2 & 3) ────────────────────────────────

  /// Pushes the on-device ML Kit suggestion into the form: auto-selects the
  /// category and appends the detected colour as a tag. The user can still
  /// override everything (the dropdown is the human-in-the-loop control).
  // ── AI auto-classification (Modules 2 & 3, Algorithm 4.7.1) ───────────────

  /// Applies the AI result according to its confidence tier:
  ///  - HIGH (>=75%): auto-fill category + description (+ colour/brand tags)
  ///  - MEDIUM (50-75%): user picks from suggested category chips
  ///  - LOW (<50%): nothing auto-filled; the user enters details manually
  void _applySuggestion(ReportItemViewModel vm) {
    final c = vm.classification;
    if (c == null || !mounted) return;
    if (c.isHigh) {
      setState(
        () => _fillFromAi(
          c.category,
          c.description,
          c.colorName,
          c.possibleBrand,
        ),
      );
    }
    // medium/low: wait for the user (chips / manual dropdown)
  }

  /// Commits an AI category + description into the form fields.
  void _fillFromAi(
    String category,
    String description,
    String colorName,
    String? brand,
  ) {
    if (ClassificationService.categories.contains(category)) {
      _selectedCategory = category;
      _selectedQuestion = null; // question list depends on category
    }
    if (description.isNotEmpty && _descCtrl.text.trim().isEmpty) {
      _descCtrl.text = description;
    }
  }

  /// Medium-tier: the user taps one of the suggested category chips.
  void _chooseSuggestion(ReportItemViewModel vm, CategorySuggestion sug) {
    final c = vm.classification;
    setState(
      () => _fillFromAi(
        sug.category,
        c?.description ?? '',
        c?.colorName ?? 'Unknown',
        c?.possibleBrand,
      ),
    );
  }

  Widget _aiSuggestionSection(ReportItemViewModel vm) {
    if (vm.isClassifying) {
      return _infoCard(
        const Color(0xFFDDE3F0),
        Colors.white,
        const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text(
              'Analysing image on-device…',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }
    final c = vm.classification;
    if (c == null) return const SizedBox.shrink();
    switch (c.tier) {
      case ConfidenceTier.high:
        return _highCard(c);
      case ConfidenceTier.medium:
        return _mediumCard(vm, c);
      case ConfidenceTier.low:
        return _lowCard();
    }
  }

  Widget _cardHeader(
    IconData icon,
    String title,
    Color accent, {
    double? confidence,
  }) {
    return Row(
      children: [
        Icon(icon, color: accent, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
        if (confidence != null && confidence > 0)
          Text(
            'Label ${(confidence * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
      ],
    );
  }

  List<Widget> _attributeChips(dynamic c) => [
    _chip(Icons.category_outlined, c.category),
    if (c.colorName != 'Unknown')
      _chip(Icons.palette_outlined, c.colorName, swatchHex: c.colorHex),
    if (c.material != null) _chip(Icons.texture_rounded, c.material as String),
    if (c.possibleBrand != null)
      _chip(Icons.sell_outlined, 'Brand? ${c.possibleBrand}'),
  ];

  // HIGH (>=75%) — auto-filled, green.
  Widget _highCard(dynamic c) {
    const accent = _teal;
    return _infoCard(
      accent.withValues(alpha: 0.5),
      const Color(0xFFE8F5E9),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            Icons.auto_awesome_rounded,
            'AI Suggestion · Auto-filled',
            accent,
            confidence: c.confidence as double,
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: _attributeChips(c)),
          const SizedBox(height: 10),
          Text(
            'Category and description filled automatically. You can edit any '
            'field below before submitting.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.green.shade900,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // MEDIUM (50-75%) — pick from suggestions, blue.
  Widget _mediumCard(ReportItemViewModel vm, dynamic c) {
    const accent = _primaryBlue;
    final List<CategorySuggestion> sugs = (c.suggestions as List)
        .cast<CategorySuggestion>();
    return _infoCard(
      accent.withValues(alpha: 0.4),
      const Color(0xFFE3F2FD),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            Icons.help_outline_rounded,
            'Not fully sure — pick a category',
            accent,
            confidence: c.confidence as double,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final sug in sugs)
                _suggestionActionChip(
                  '${sug.category} · label ${(sug.confidence * 100).toStringAsFixed(0)}%',
                  () => _chooseSuggestion(vm, sug),
                ),
            ],
          ),
          if (c.colorName != 'Unknown' || c.possibleBrand != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (c.colorName != 'Unknown')
                  _chip(
                    Icons.palette_outlined,
                    c.colorName as String,
                    swatchHex: c.colorHex as String,
                  ),
                if (c.possibleBrand != null)
                  _chip(Icons.sell_outlined, 'Brand? ${c.possibleBrand}'),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Tap a suggestion to fill the form, or choose manually below.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.blue.shade900,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // LOW (<50%) — unrecognized, orange.
  Widget _lowCard() {
    const accent = Color(0xFFE65100);
    return _infoCard(
      accent.withValues(alpha: 0.5),
      const Color(0xFFFFF3E0),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            Icons.error_outline_rounded,
            'Item not recognized',
            accent,
          ),
          const SizedBox(height: 8),
          Text(
            'The AI could not confidently identify this item. Please choose the '
            'category and enter a description manually.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.brown.shade800,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(Color border, Color bg, Widget child) => Container(
    margin: const EdgeInsets.only(top: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: border),
    ),
    child: child,
  );

  Widget _suggestionActionChip(String label, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _primaryBlue.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, size: 16, color: _primaryBlue),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _primaryBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, {String? swatchHex}) {
    Color? swatch;
    if (swatchHex != null) {
      swatch = Color(int.parse(swatchHex.replaceFirst('#', '0xFF')));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE3F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (swatch != null)
            Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: swatch,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black12),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(icon, size: 15, color: const Color(0xFF607D8B)),
            ),
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ── Date Found field (FR 2.5) ─────────────────────────────────────────────

  Widget _dateField() {
    final d = _dateFound;
    final text = d == null
        ? 'Select date'
        : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: _inputDeco(hint: 'Select date', icon: Icons.event_outlined),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            color: d == null ? const Color(0xFFBDBDBD) : null,
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFound ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (picked != null) setState(() => _dateFound = picked);
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
                    child: const Icon(
                      Icons.add_a_photo_rounded,
                      color: _primaryBlue,
                      size: 32,
                    ),
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
                    widget.isLost
                        ? 'Camera or Gallery (optional)'
                        : 'Camera or Gallery',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
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
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 18,
                        ),
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
              hint: 'Select category',
              icon: Icons.category_outlined,
            ),
            items: _categories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() {
                  _selectedCategory = v;
                  _selectedQuestion =
                      null; // reset — questions depend on category
                });
              }
            },
            validator: (v) =>
                v == null ? 'Please select an item category.' : null,
          ),
          const SizedBox(height: 20),
          _label(
            widget.isLost ? 'Where did you last see it?' : 'Location Found *',
          ),
          const SizedBox(height: 8),
          // Level 1 — building / area
          DropdownButtonFormField<String>(
            value: _selectedArea,
            isExpanded: true,
            decoration: _inputDeco(
              hint: 'Select building / area',
              icon: Icons.apartment_rounded,
            ),
            items: _areas
                .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                .toList(),
            onChanged: (v) => setState(() {
              _selectedArea = v;
              _selectedSpot = null; // reset — spots depend on the area
            }),
            validator: (v) {
              if (widget.isLost) return null;
              return v == null ? 'Please select a building / area.' : null;
            },
          ),
          // Level 2 — specific spot (appears after an area is chosen)
          if (_selectedArea != null) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedSpot,
              isExpanded: true,
              decoration: _inputDeco(
                hint: 'Select specific spot',
                icon: Icons.place_outlined,
              ),
              items: _currentSpots
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(s, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _selectedSpot = v),
              validator: (v) {
                if (widget.isLost) return null;
                return v == null ? 'Please select a specific spot.' : null;
              },
            ),
          ],
          // Free-text only when "Other (specify)" is chosen
          if (_selectedSpot == _otherSpot) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _locationCtrl,
              textInputAction: TextInputAction.next,
              decoration: _inputDeco(
                hint: 'e.g. near the printer, Level 2',
                icon: Icons.edit_location_alt_outlined,
              ),
              validator: (v) {
                if (_selectedSpot == _otherSpot &&
                    (v == null || v.trim().isEmpty)) {
                  return 'Please describe the exact spot.';
                }
                return null;
              },
            ),
          ],
          const SizedBox(height: 20),
          if (!widget.isLost) ...[
            _label('Date Found *'),
            const SizedBox(height: 8),
            _dateField(),
            const SizedBox(height: 20),
          ],
          _label('Description *'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _descCtrl,
            maxLines: 3,
            textInputAction: TextInputAction.next,
            decoration: _inputDeco(
              hint: widget.isLost
                  ? 'Describe your item — colour, brand, marks…'
                  : 'Any distinguishing features, colour, brand…',
              icon: Icons.notes_rounded,
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Description is required.'
                : null,
          ),

          // Ownership-verification quiz — found items only (FR 5.2)
          if (!widget.isLost) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFE082)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    color: Color(0xFFE65100),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Set a security question only the real owner can answer. '
                      'Claimants must answer it before they can contact you.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.brown.shade700,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _label(
              'Ownership Question  (${_selectedCategory ?? 'Select category first'})',
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedQuestion,
              isExpanded: true,
              decoration: _inputDeco(
                hint: 'Choose a question for this category',
                icon: Icons.help_outline_rounded,
              ),
              items: [
                for (final q in _currentQuestions)
                  DropdownMenuItem(
                    value: q,
                    child: Text(q, overflow: TextOverflow.ellipsis),
                  ),
                const DropdownMenuItem(
                  value: _customQuestion,
                  child: Text('✏️  Write my own question'),
                ),
              ],
              onChanged: (v) => setState(() => _selectedQuestion = v),
              validator: (v) =>
                  v == null ? 'Please choose a security question.' : null,
            ),
            // Free-text field only when "Write my own question" is chosen.
            if (_selectedQuestion == _customQuestion) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _questionCtrl,
                textInputAction: TextInputAction.next,
                decoration: _inputDeco(
                  hint: 'Type your own question',
                  icon: Icons.edit_outlined,
                ),
                validator: (v) {
                  if (_selectedQuestion == _customQuestion &&
                      (v == null || v.trim().isEmpty)) {
                    return 'Please write your question.';
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: 16),
            _label('Correct Answer'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _answerCtrl,
              textInputAction: TextInputAction.done,
              decoration: _inputDeco(
                hint: 'e.g. Red',
                icon: Icons.key_outlined,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Please set the correct answer.';
                }
                return null;
              },
            ),
          ],
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
        icon: Icon(
          widget.isLost
              ? Icons.report_gmailerrorred_rounded
              : Icons.cloud_upload_rounded,
        ),
        label: Text(
          widget.isLost ? 'Submit Lost Report' : 'Upload & Process Image',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.isLost ? _primaryBlue : _teal,
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
        contentPadding: const EdgeInsets.symmetric(
          vertical: 15,
          horizontal: 16,
        ),
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
          borderSide: const BorderSide(color: Color(0xFFD32F2F), width: 1.8),
        ),
      );
}
