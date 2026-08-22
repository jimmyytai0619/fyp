import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/analytics_viewmodel.dart';

class AnalyticsView extends StatefulWidget {
  const AnalyticsView({super.key});

  @override
  State<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<AnalyticsView> {
  static const _primaryBlue = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      context.read<AnalyticsViewModel>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Insights & Analytics',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: Consumer<AnalyticsViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) {
            return const Center(
                child: CircularProgressIndicator(color: _primaryBlue));
          }
          if (vm.errorMessage != null) {
            return Center(child: Text(vm.errorMessage!));
          }
          return RefreshIndicator(
            onRefresh: () => vm.load(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Stat tiles
                Row(
                  children: [
                    _StatTile(
                        label: 'Items Found',
                        value: '${vm.total}',
                        icon: Icons.inventory_2_rounded,
                        color: const Color(0xFF1565C0)),
                    const SizedBox(width: 12),
                    _StatTile(
                        label: 'Returned',
                        value: '${vm.returned}',
                        icon: Icons.check_circle_rounded,
                        color: const Color(0xFF2E7D32)),
                  ],
                ),
                const SizedBox(height: 12),
                _ReturnRateCard(rate: vm.returnRate),
                const SizedBox(height: 24),
                _BarSection(
                  title: 'Most Common Categories',
                  icon: Icons.category_rounded,
                  data: vm.byCategory,
                  barColor: const Color(0xFF1565C0),
                ),
                const SizedBox(height: 24),
                _BarSection(
                  title: 'Hotspot Buildings',
                  icon: Icons.location_on_rounded,
                  data: vm.byBuilding,
                  barColor: const Color(0xFFE65100),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatTile(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 10),
            Text(value,
                style: TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w800, color: color)),
            Text(label,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}

class _ReturnRateCard extends StatelessWidget {
  final double rate;
  const _ReturnRateCard({required this.rate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Overall Return Rate',
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              Text('${rate.toStringAsFixed(0)}%',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2E7D32))),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (rate / 100).clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: const Color(0xFFECEFF1),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF2E7D32)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<MapEntry<String, int>> data;
  final Color barColor;
  const _BarSection(
      {required this.title,
      required this.icon,
      required this.data,
      required this.barColor});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    final max = data.first.value.toDouble();
    final top = data.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: barColor),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 12),
        ...top.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(e.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      Text('${e.value}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: max == 0 ? 0 : (e.value / max).clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: const Color(0xFFECEFF1),
                      valueColor: AlwaysStoppedAnimation<Color>(barColor),
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}
