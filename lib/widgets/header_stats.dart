import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/payments_provider.dart';
import '../utils/week_calculator.dart';

/// Header sticky con stats de la semana SELECCIONADA.
class HeaderStats extends ConsumerWidget {
  const HeaderStats({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(currentWeekStatsProvider);
    final selectedWeek = ref.watch(selectedWeekStartProvider);
    final isCurrent = ref.watch(isCurrentWeekSelectedProvider);
    final scheme = Theme.of(context).colorScheme;

    return statsAsync.when(
      data: (stats) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(8, 40, 8, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primary, scheme.secondary],
          ),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Selector de semana con flechas ‹ ›.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  icon: const Icon(Icons.chevron_left, color: Colors.white),
                  onPressed: () {
                    ref.read(selectedWeekStartProvider.notifier).state =
                        selectedWeek.subtract(const Duration(days: 7));
                  },
                ),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isCurrent
                            ? 'Semana actual'
                            : 'Semana pasada',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 1),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          WeekCalculator.label(
                            selectedWeek,
                            WeekCalculator.weekEnd(selectedWeek),
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  icon: const Icon(Icons.chevron_right, color: Colors.white),
                  onPressed: isCurrent
                      ? null
                      : () {
                          ref.read(selectedWeekStartProvider.notifier).state =
                              selectedWeek.add(const Duration(days: 7));
                        },
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 3 stat cards
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.check_circle_rounded,
                    label: 'Pagaron',
                    value: '${stats.paidCount}/${stats.totalMembers}',
                    sublabel: stats.paidCount == 1 ? 'persona' : 'personas',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    icon: Icons.attach_money_rounded,
                    label: 'Recaudado',
                    value: _formatMoney(stats.totalCollected),
                    sublabel: 'de ${_formatMoney(stats.expectedThisWeek)}',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    icon: Icons.schedule_rounded,
                    label: 'Restante',
                    value: '${stats.daysRemaining}',
                    sublabel: stats.daysRemaining == 1 ? 'día' : 'días',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      loading: () => Container(
        height: 200,
        color: scheme.primary,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
      error: (e, _) => Container(
        height: 200,
        color: scheme.errorContainer,
        child: Center(
          child: Text('Error: $e',
              style: TextStyle(color: scheme.onErrorContainer)),
        ),
      ),
    );
  }

  String _formatMoney(double v) => '\$${v.toStringAsFixed(2)}';
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String sublabel;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 14),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            sublabel,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}
