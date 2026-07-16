import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/payment.dart';
import '../utils/week_calculator.dart';
import 'members_provider.dart';
import 'repositories_provider.dart';

/// Semana que está viendo el usuario en la HomeScreen.
/// Inicia en la semana actual; se puede cambiar con los botones ‹ ›.
final selectedWeekStartProvider = StateProvider<DateTime>((ref) {
  return WeekCalculator.currentWeekStart();
});

/// True si la semana seleccionada es la actual.
final isCurrentWeekSelectedProvider = Provider<bool>((ref) {
  final selected = ref.watch(selectedWeekStartProvider);
  return selected == WeekCalculator.currentWeekStart();
});

/// Pagos de la semana seleccionada.
final currentWeekPaymentsProvider =
    FutureProvider<List<Payment>>((ref) async {
  final weekStart = ref.watch(selectedWeekStartProvider);
  return ref.watch(paymentRepositoryProvider).getForWeek(weekStart);
});

/// Estado del pago (memberId -> Payment?) para la semana seleccionada.
final currentWeekStatusProvider =
    FutureProvider<Map<int, Payment?>>((ref) async {
  final members = await ref.watch(currentWeekPaymentsProvider.future);
  return {for (final p in members) p.memberId: p};
});

/// Stats de la semana seleccionada.
class WeekStats {
  final int paidCount;
  final double totalCollected;
  final int totalMembers;
  final int daysRemaining;

  const WeekStats({
    required this.paidCount,
    required this.totalCollected,
    required this.totalMembers,
    required this.daysRemaining,
  });

  int get pendingCount => totalMembers - paidCount;
  double get expectedThisWeek => totalMembers * 1.75;
}

final currentWeekStatsProvider = FutureProvider<WeekStats>((ref) async {
  final payments = await ref.watch(currentWeekPaymentsProvider.future);
  final members = await ref.watch(membersProvider.future);
  final totalMembers = members.length;
  final paidCount = payments.length;
  final total = payments.fold<double>(0, (acc, p) => acc + p.amount);
  return WeekStats(
    paidCount: paidCount,
    totalCollected: total,
    totalMembers: totalMembers,
    daysRemaining: WeekCalculator.daysRemainingThisWeek(),
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

  /// Marca a un miembro como pagado esta semana, con captura opcional.
  /// Si ya tenía un pago lo reemplaza (sumando el path de captura nuevo).
  /// Retorna el `Payment` resultante (nuevo o actualizado).
  Future<Payment> markPaid({
    required int memberId,
    required double amount,
    String? screenshotPath,
  }) async {
    final repo = _ref.read(paymentRepositoryProvider);
    final weekStart = _ref.read(selectedWeekStartProvider);
    final weekEnd = WeekCalculator.weekEnd(weekStart);
    final path = (screenshotPath != null && screenshotPath.isNotEmpty)
        ? screenshotPath
        : null;
    final existing = await repo.getForMemberWeek(memberId, weekStart);
    if (existing != null) {
      // Actualizar (re-asignar capture si viene una nueva)
      final updated = existing.copyWith(
        amount: amount,
        paidAt: DateTime.now(),
        screenshotPath: path ?? existing.screenshotPath,
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
      paidAt: DateTime.now(),
      screenshotPath: path,
    );
    await repo.upsert(created);
    _refresh();
    return created;
  }

  /// Quita el pago de un miembro en la semana seleccionada. La captura
  /// adjunta se pierde con el delete.
  Future<void> unmarkPaid(int memberId) async {
    final repo = _ref.read(paymentRepositoryProvider);
    final weekStart = _ref.read(selectedWeekStartProvider);
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
