import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_repository.dart';
import '../models/payment.dart';
import '../utils/week_calculator.dart';
import 'members_provider.dart';
import 'repositories_provider.dart';
import 'settings_provider.dart';

/// Semana que está viendo el usuario en la HomeScreen.
/// Inicia en la semana actual; se puede cambiar con el datepicker.
final selectedWeekStartProvider = StateProvider<DateTime>((ref) {
  return WeekCalculator.currentWeekStart();
});

/// True si la semana seleccionada es la actual.
final isCurrentWeekSelectedProvider = Provider<bool>((ref) {
  final selected = ref.watch(selectedWeekStartProvider);
  return selected == WeekCalculator.currentWeekStart();
});

/// Pagos que cubren la semana seleccionada.
final currentWeekPaymentsProvider =
    FutureProvider<List<Payment>>((ref) async {
  final weekStart = ref.watch(selectedWeekStartProvider);
  return ref.watch(paymentRepositoryProvider).getForWeek(weekStart);
});

/// Estado del pago (memberId -> Payment?) para la semana seleccionada.
final currentWeekStatusProvider =
    FutureProvider<Map<int, Payment?>>((ref) async {
  final payments = await ref.watch(currentWeekPaymentsProvider.future);
  // Si un miembro tiene varios pagos que cubren la misma semana
  // (poco probable, pero posible), tomar el más reciente.
  final byMember = <int, Payment>{};
  for (final p in payments) {
    final existing = byMember[p.memberId];
    if (existing == null || p.paidAt.isAfter(existing.paidAt)) {
      byMember[p.memberId] = p;
    }
  }
  return {for (final entry in byMember.entries) entry.key: entry.value};
});

class WeekStats {
  final int paidCount;
  final double totalCollected;
  final int totalMembers;
  final int daysRemaining;
  final double expectedThisWeek;

  const WeekStats({
    required this.paidCount,
    required this.totalCollected,
    required this.totalMembers,
    required this.daysRemaining,
    required this.expectedThisWeek,
  });

  int get pendingCount => totalMembers - paidCount;
}

final currentWeekStatsProvider = FutureProvider<WeekStats>((ref) async {
  final payments = await ref.watch(currentWeekPaymentsProvider.future);
  final members = await ref.watch(membersProvider.future);
  final totalMembers = members.length;
  final paidCount = payments.length;
  // Sumar la fracción de cada pago que corresponde a esta semana.
  final total = payments.fold<double>(0, (acc, p) {
    final perWeek = p.weeksCovered > 0 ? p.amount / p.weeksCovered : 0;
    return acc + perWeek;
  });
  // Esperado: tarifa de 2 clases × miembros (asumimos 2 clases como
  // tarifa "promedio" para el cálculo agregado).
  final settings = ref.watch(settingsSyncProvider);
  final defaultTier = settings.feeTees.isNotEmpty
      ? settings.feeTees.first
      : const FeeTier(classes: 2, amount: 2.5);
  final expected = totalMembers * defaultTier.amount;
  return WeekStats(
    paidCount: paidCount,
    totalCollected: total,
    totalMembers: totalMembers,
    daysRemaining: WeekCalculator.daysRemainingThisWeek(),
    expectedThisWeek: expected,
  );
});

/// Historial de pagos de un miembro específico.
final memberHistoryProvider =
    FutureProvider.family<List<Payment>, int>((ref, memberId) async {
  return ref.watch(paymentRepositoryProvider).getForMember(memberId);
});

/// Pagos de una semana arbitraria (para WeekHistoryScreen).
final weekPaymentsProvider =
    FutureProvider.family<List<Payment>, DateTime>((ref, weekStart) async {
  return ref.watch(paymentRepositoryProvider).getForWeek(weekStart);
});

class PaymentsNotifier extends StateNotifier<int> {
  final Ref _ref;
  PaymentsNotifier(this._ref) : super(0);

  /// Marca a un miembro como pagado.
  ///
  /// - [memberId]: el miembro
  /// - [amount]: el monto total pagado (puede ser cualquier valor)
  /// - [weekStart]: semana del pago (lunes)
  /// - [classesAttended]: clases tomadas esa semana
  /// - [weeksCovered]: cuántas semanas cubre el pago (>= 1)
  /// - [screenshotPath]: opcional
  Future<Payment> markPaid({
    required int memberId,
    required double amount,
    required DateTime weekStart,
    int classesAttended = 2,
    int? weeksCovered,
    String? screenshotPath,
  }) async {
    final repo = _ref.read(paymentRepositoryProvider);
    final weekEnd = WeekCalculator.weekEnd(weekStart);
    final path = (screenshotPath != null && screenshotPath.isNotEmpty)
        ? screenshotPath
        : null;

    // Si no se pasan weeksCovered, intentar inferirlo dividiendo por la
    // tarifa vigente para la cantidad de clases. Si no se puede, 1.
    int covered = weeksCovered ?? 1;
    if (weeksCovered == null) {
      final settings = _ref.read(settingsSyncProvider);
      final tier = settings.amountFor(classesAttended);
      if (tier != null && tier > 0) {
        covered = (amount / tier).floor();
        if (covered < 1) covered = 1;
      }
    }

    final existing = await repo.getForMemberWeek(memberId, weekStart);
    if (existing != null) {
      // Actualizar (re-asignar capture si viene una nueva)
      final updated = Payment(
        id: existing.id,
        memberId: memberId,
        weekStart: weekStart,
        weekEnd: weekEnd,
        amount: amount,
        classesAttended: classesAttended,
        weeksCovered: covered,
        paidAt: DateTime.now(),
        screenshotPath: path ?? existing.screenshotPath,
        note: existing.note,
      );
      await repo.upsert(updated);
      _refresh();
      return updated;
    }
    final created = Payment(
      memberId: memberId,
      weekStart: weekStart,
      weekEnd: weekEnd,
      amount: amount,
      classesAttended: classesAttended,
      weeksCovered: covered,
      paidAt: DateTime.now(),
      screenshotPath: path,
    );
    await repo.upsert(created);
    _refresh();
    return created;
  }

  /// Quita el pago de un miembro en la semana indicada.
  Future<void> unmarkPaid(int memberId, DateTime weekStart) async {
    final repo = _ref.read(paymentRepositoryProvider);
    final existing = await repo.getForMemberWeek(memberId, weekStart);
    if (existing == null) return;
    await repo.delete(existing.id!);
    _refresh();
  }

  /// Actualiza solo la captura de un pago específico.
  Future<void> updateScreenshot(int paymentId, String? path) async {
    final repo = _ref.read(paymentRepositoryProvider);
    await repo.setScreenshot(paymentId, path);
    _refresh();
  }

  /// Elimina un pago completo (y su captura).
  Future<void> deletePayment(int id) async {
    final repo = _ref.read(paymentRepositoryProvider);
    await repo.delete(id);
    _refresh();
  }

  void _refresh() {
    _ref.invalidate(currentWeekPaymentsProvider);
    _ref.invalidate(currentWeekStatsProvider);
    _ref.invalidate(currentWeekStatusProvider);
    _ref.invalidate(memberHistoryProvider);
  }
}

final paymentsNotifierProvider =
    StateNotifierProvider<PaymentsNotifier, int>((ref) {
  return PaymentsNotifier(ref);
});
