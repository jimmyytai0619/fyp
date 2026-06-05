import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/match_result.dart';
import '../../viewmodels/search_viewmodel.dart';
import 'item_detail_view.dart';

class SearchView extends StatelessWidget {
  const SearchView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SearchViewModel(),
      child: const _SearchScaffold(),
    );
  }
}

class _SearchScaffold extends StatelessWidget {
  const _SearchScaffold();

  static const _primaryBlue = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SearchViewModel>();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        title: const Text('AI Visual Search',
            style: TextStyle(fontWeight: FontWeight.w700)),
        elevation: 0,
        actions: [
          if (vm.state != SearchState.idle || vm.referenceImage != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Start over',
              onPressed: () => context.read<SearchViewModel>().clearSearch(),
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: switch (vm.state) {
          SearchState.idle => _PreSearchPanel(key: const ValueKey('pre')),
          SearchState.loading =>
            _LoadingPanel(key: const ValueKey('loading')),
          SearchState.results => _ResultsPanel(
              key: const ValueKey('results'),
              results: vm.searchResults,
            ),
          SearchState.error => _ErrorPanel(
              key: const ValueKey('error'),
              message: vm.errorMessage,
            ),
          _ => _PreSearchPanel(key: const ValueKey('pre2')),
        },
      ),
    );
  }
}

// ── Pre-Search Panel ──────────────────────────────────────────────────────────

class _PreSearchPanel extends StatelessWidget {
  const _PreSearchPanel({super.key});

  static const _primaryBlue = Color(0xFF1565C0);

  void _showSourceSheet(BuildContext context) {
    final vm = context.read<SearchViewModel>();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            const Text('Select Image Source',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
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
                child: Icon(Icons.photo_library_rounded,
                    color: Color(0xFF00897B)),
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

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SearchViewModel>();
    final hasImage = vm.referenceImage != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          _buildHeroCard(),
          const SizedBox(height: 28),
          // Upload area
          GestureDetector(
            onTap: () => _showSourceSheet(context),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: hasImage
                      ? _primaryBlue
                      : _primaryBlue.withValues(alpha: 0.3),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _primaryBlue.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: hasImage
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(vm.referenceImage!, fit: BoxFit.cover),
                        Container(
                          color: Colors.black.withValues(alpha: 0.35),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.edit_outlined,
                                  color: Colors.white, size: 30),
                              SizedBox(height: 8),
                              Text('Tap to change photo',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: _primaryBlue.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.image_search_rounded,
                              color: _primaryBlue, size: 34),
                        ),
                        const SizedBox(height: 14),
                        const Text('Upload Reference Photo',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: _primaryBlue)),
                        const SizedBox(height: 4),
                        Text('Camera or Gallery',
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade500)),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 24),

          // Search button
          AnimatedOpacity(
            opacity: hasImage ? 1.0 : 0.45,
            duration: const Duration(milliseconds: 250),
            child: SizedBox(
              height: 54,
              child: ElevatedButton.icon(
                onPressed:
                    hasImage ? () => vm.executeVisualSearch() : null,
                icon: const Icon(Icons.search_rounded),
                label: const Text('Search with AI',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      _primaryBlue.withValues(alpha: 0.5),
                  elevation: 3,
                  shadowColor: _primaryBlue.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),

          if (!hasImage) ...[
            const SizedBox(height: 20),
            _buildHowItWorks(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeroCard() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Use AI Visual Search',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  SizedBox(height: 4),
                  Text(
                    'Upload a photo of your lost item and our AI will scan the database for visual matches.',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildHowItWorks() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('How it works',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF37474F))),
            const SizedBox(height: 12),
            _step('1', 'Upload a clear photo of your lost item'),
            _step('2', 'AI scans the found-items database'),
            _step('3', 'Review matches ranked by similarity score'),
          ],
        ),
      );

  Widget _step(String num, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                  color: Color(0xFFE3F2FD), shape: BoxShape.circle),
              child: Center(
                child: Text(num,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1565C0))),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(text,
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF546E7A)))),
          ],
        ),
      );
}

// ── Loading Panel ─────────────────────────────────────────────────────────────

class _LoadingPanel extends StatefulWidget {
  const _LoadingPanel({super.key});

  @override
  State<_LoadingPanel> createState() => _LoadingPanelState();
}

class _LoadingPanelState extends State<_LoadingPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  static const _steps = [
    'Uploading reference image...',
    'Extracting visual features...',
    'Scanning database vectors...',
    'Ranking similarity scores...',
  ];
  int _stepIndex = 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);

    // Cycle through step labels every 1.4 s for a realistic feel.
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 1400));
      if (!mounted) return false;
      setState(() => _stepIndex = (_stepIndex + 1) % _steps.length);
      return true;
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.lerp(
                    const Color(0xFFE3F2FD),
                    const Color(0xFF1565C0).withValues(alpha: 0.15),
                    _pulse.value,
                  ),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: CircularProgressIndicator(
                      strokeWidth: 3.5,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            const Text('AI is scanning database vectors...',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0D2B6B))),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Text(
                _steps[_stepIndex],
                key: ValueKey(_stepIndex),
                style: TextStyle(
                    fontSize: 13.5, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Results Panel ─────────────────────────────────────────────────────────────

class _ResultsPanel extends StatelessWidget {
  final List<MatchResult> results;

  const _ResultsPanel({super.key, required this.results});

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded,
                  size: 72, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text('No matches found',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF37474F))),
              const SizedBox(height: 8),
              Text(
                'Try a clearer photo or a different angle.',
                style: TextStyle(
                    fontSize: 14, color: Colors.grey.shade500),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 18, color: Color(0xFF1565C0)),
              const SizedBox(width: 8),
              Text(
                '${results.length} match${results.length == 1 ? '' : 'es'} found',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Color(0xFF1565C0)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: results.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) =>
                _MatchCard(item: results[i]),
          ),
        ),
      ],
    );
  }
}

// ── Match Card ────────────────────────────────────────────────────────────────

class _MatchCard extends StatelessWidget {
  final MatchResult item;

  const _MatchCard({required this.item});

  static const _primaryBlue = Color(0xFF1565C0);

  Color get _badgeColor {
    if (item.confidenceScore >= 90) return const Color(0xFF2E7D32);
    if (item.confidenceScore >= 70) return const Color(0xFFF57F17);
    return const Color(0xFFC62828);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => ItemDetailView(item: item)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(18)),
              child: item.imageUrl.isNotEmpty
                  ? Image.network(
                      item.imageUrl,
                      width: 110,
                      height: 110,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _placeholderThumb(),
                    )
                  : _placeholderThumb(),
            ),

            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _badgeColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome,
                              color: Colors.white, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            '${item.confidenceScore.toStringAsFixed(1)}%',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      item.category,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Color(0xFF1A237E)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 4),

                    Row(
                      children: [
                        Icon(Icons.location_on_outlined,
                            size: 13,
                            color: Colors.grey.shade500),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            item.locationFound,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'View Details',
                          style: const TextStyle(
                              fontSize: 12,
                              color: _primaryBlue,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.chevron_right_rounded,
                            size: 16, color: _primaryBlue),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholderThumb() => Container(
        width: 110,
        height: 110,
        color: const Color(0xFFE3F2FD),
        child: const Icon(Icons.image_outlined,
            color: Color(0xFF1565C0), size: 36),
      );
}

// ── Error Panel ───────────────────────────────────────────────────────────────

class _ErrorPanel extends StatelessWidget {
  final String message;

  const _ErrorPanel({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                  color: Color(0xFFFFEBEE), shape: BoxShape.circle),
              child: const Icon(Icons.wifi_off_rounded,
                  color: Color(0xFFC62828), size: 38),
            ),
            const SizedBox(height: 20),
            const Text('Search Failed',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF37474F))),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.5, color: Colors.grey.shade600)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () =>
                  context.read<SearchViewModel>().executeVisualSearch(),
            ),
          ],
        ),
      ),
    );
  }
}
