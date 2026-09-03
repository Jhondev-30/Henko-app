import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_config.dart';
import '../providers/members_provider.dart';
import '../providers/payments_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../utils/week_calculator.dart';

class WeekHistoryScreen extends ConsumerStatefulWidget {
  const WeekHistoryScreen({super.key});

  @override
  ConsumerState<WeekHistoryScreen> createState() =>
      _WeekHistoryScreenState();
}

class _WeekHistoryScreenState extends ConsumerState<WeekHistoryScreen> {
  late DateTime _selectedWeekStart;

  @override
  void initState() {
    super.initState();
    _selectedWeekStart = WeekCalculator.currentWeekStart();
  }

  void _changeWeek(int deltaWeeks) {
    setState(() {
      _selectedWeekStart =
          _selectedWeekStart.add(Duration(days: 7 * deltaWeeks));
    });
  }

  double _defaultFee() {
    final s = ref.watch(settingsSyncProvider);
    return s.feeTees.isNotEmpty ? s.feeTees.first.amount : 2.5;
  }

  @override
  Widget build(BuildContext context) {
    final paymentsAsync =
        ref.watch(weekPaymentsProvider(_selectedWeekStart));
    final membersAsync = ref.watch(membersProvider);
    final isCurrentWeek =
        _selectedWeekStart == WeekCalculator.currentWeekStart();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Historial por semana')),
      body: Column(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            color: Colors.white,
            child: Row(
              children: [
                IconButton.filledTonal(
                  onPressed: () => _changeWeek(1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      children: [
                        Text(
                          isCurrentWeek
                              ? 'Semana actual'
                              : 'Semana pasada',
                          style: const TextStyle(
                            color: AppTheme.brandPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          WeekCalculator.label(
                            _selectedWeekStart,
                            WeekCalculator.weekEnd(_selectedWeekStart),
                          ),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed:
                      isCurrentWeek ? null : () => _changeWeek(-1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(
            child: paymentsAsync.when(
              data: (payments) {
                return membersAsync.when(
                  data: (members) {
                    final paidIds = payments.map((p) => p.memberId).toSet();
                    final paid = members
                        .where((m) => paidIds.contains(m.id))
                        .toList();
                    final pending = members
                        .where((m) => !paidIds.contains(m.id))
                        .toList();
                    final total = payments.fold<double>(
                        0, (acc, p) => acc + p.amount);

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          color: scheme.primaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceAround,
                              children: [
                                _StatBlock(
                                    label: 'Pagaron',
                                    value: '${paid.length}',
                                    sub: 'de ${members.length}',
                                    color: AppTheme.success),
                                Container(
                                    width: 1,
                                    height: 40,
                                    color: scheme.outlineVariant),
                                _StatBlock(
                                    label: 'Recaudado',
                                    value: CurrencyFormatter.format(total),
                                    sub:
                                        'esperado ${CurrencyFormatter.format(members.length * _defaultFee())}',
                                    color: AppTheme.brandSecondary),
                                Container(
                                    width: 1,
                                    height: 40,
                                    color: scheme.outlineVariant),
                                _StatBlock(
                                    label: 'Pendientes',
                                    value: '${pending.length}',
                                    sub: 'faltan',
                                    color: AppTheme.error),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _Section(
                          title: '✅ Pagaron (${paid.length})',
                          color: AppTheme.success,
                          emptyText: 'Nadie pagó esta semana',
                          members: paid,
                        ),
                        const SizedBox(height: 16),
                        _Section(
                          title: '⏳ Pendientes (${pending.length})',
                          color: AppTheme.error,
                          emptyText: '¡Todos pagaron! 🎉',
                          members: pending,
                        ),
                      ],
                    );
                  },
                  loading: () => const Center(
                      child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color color;
  const _StatBlock({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
              )),
          Text(sub,
              style: const TextStyle(
                  fontSize: 10, color: Colors.black45)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Color color;
  final String emptyText;
  final List members;
  const _Section({
    required this.title,
    required this.color,
    required this.emptyText,
    required this.members,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (members.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(AppTheme.rMd),
            ),
            child: Text(emptyText,
                style: TextStyle(color: Colors.grey.shade600)),
          )
        else
          ...members.map((m) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                  border: Border.all(
                      color: color.withValues(alpha: 0.3), width: 1),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        color: color, size: 18),
                    const SizedBox(width: 10),
                    Text(m.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                  ],
                ),
              )),
      ],
    );
  }
}
