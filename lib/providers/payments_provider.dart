import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/payment.dart';
import '../utils/week_calculator.dart';
import 'members_provider.dart';
import 'repositories_provider.dart';
import 'settings_provider.dart';

/// Semana que está viendo el usuario en la HomeScreen.
final selectedWeekStartProvider = StateProvider<DateTime>((ref) {
  return WeekCalculator.currentWeekStart();
});

/// True si la semana seleccionada es la actual.
final isCurrentWeekSelectedProvider = Provider<bool>((ref) {
  final selected = ref.watch(selectedWeekStartProvider);
  return selected == WeekCalculator.currentWeekStart();
});

/// Pagos que cubren la semana seleccionada (según classesPerWeek actual).
final currentWeekPaymentsProvider =
    FutureProvider<List<Payment>>((ref) async {
  final weekStart = ref.watch(selectedWeekStartProvider);
  final settings = ref.watch(settingsSyncProvider);
  return ref
      .watch(paymentRepositoryProvider)
      .getForWeek(weekStart, settings.defaultClassesPerWeek);
});

/// Estado del pago (memberId -> Payment?) para la semana seleccionada.
/// Si un miembro tiene varios pagos, tomar el más reciente.
final currentWeekStatusProvider =
    FutureProvider<Map<int, Payment?>>((ref) async {
  final payments = await ref.watch(currentWeekPaymentsProvider.future);
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
  final int classesPerWeek;

  const WeekStats({
    required this.paidCount,
    required this.totalCollected,
    required this.totalMembers,
    required this.daysRemaining,
    required this.expectedThisWeek,
    required this.classesPerWeek,
  });

  int get pendingCount => totalMembers - paidCount;
}

final currentWeekStatsProvider = FutureProvider<WeekStats>((ref) async {
  final settings = ref.watch(settingsSyncProvider);
  final cpw = settings.defaultClassesPerWeek;
  final payments = await ref.watch(currentWeekPaymentsProvider.future);
  final members = await ref.watch(membersProvider.future);
  final totalMembers = members.length;
  final paidCount = payments.length;
  // Total REAL: por cada pago, clases que tomó esta semana × tarifa
  // per-clase **de ese pago** (amount/classesCount). Antes se usaba la
  // tarifa global, lo cual sumaba $10 completos a cada semana cuando
  // un pago era multi-semana (bug v1.5.1).
  final currentWeek = WeekCalculator.currentWeekStart();
  final total = payments.fold<double>(0, (acc, p) {
    if (p.classesCount <= 0) return acc;
    final perClass = p.amount / p.classesCount;
    final taken = p.classesTakenIn(currentWeek);
    return acc + taken * perClass;
  });
  // Esperado: tarifa de la semana × miembros
  final perClassRate = settings.perClassRate;
  final tierAmount = settings.amountFor(cpw) ?? perClassRate * cpw;
  final expected = totalMembers * tierAmount;
  return WeekStats(
    paidCount: paidCount,
    totalCollected: total,
    totalMembers: totalMembers,
    daysRemaining: WeekCalculator.daysRemainingThisWeek(),
    expectedThisWeek: expected,
    classesPerWeek: cpw,
  );
});

/// Historial de pagos de un miembro específico.
final memberHistoryProvider =
    FutureProvider.family<List<Payment>, int>((ref, memberId) async {
  return ref.watch(paymentRepositoryProvider).getForMember(memberId);
});

/// Pagos de una semana arbitraria.
final weekPaymentsProvider =
    FutureProvider.family<List<Payment>, DateTime>((ref, weekStart) async {
  final settings = ref.watch(settingsSyncProvider);
  return ref
      .watch(paymentRepositoryProvider)
      .getForWeek(weekStart, settings.defaultClassesPerWeek);
});

class PaymentsNotifier extends StateNotifier<int> {
  final Ref _ref;
  PaymentsNotifier(this._ref) : super(0);

  /// Marca a un miembro como pagado.
  ///
  /// - [memberId]: el miembro
  /// - [amount]: el monto total pagado
  /// - [weekStart]: semana del pago (lunes)
  /// - [classesCount]: total de clases que cubre el pago
  /// - [classesAttended]: clases tomadas en la semana del pago
  /// - [screenshotPath]: opcional
  Future<Payment> markPaid({
    required int memberId,
    required double amount,
    required DateTime weekStart,
    required int classesCount,
    int classesAttended = 0,
    String? screenshotPath,
  }) async {
    final repo = _ref.read(paymentRepositoryProvider);
    final weekEnd = WeekCalculator.weekEnd(weekStart);
    final path = (screenshotPath != null && screenshotPath.isNotEmpty)
        ? screenshotPath
        : null;

    final existing = await repo.getForMemberWeek(memberId, weekStart);
    if (existing != null) {
      final updated = Payment(
        id: existing.id,
        memberId: memberId,
        weekStart: weekStart,
        weekEnd: weekEnd,
        amount: amount,
        classesCount: classesCount,
        classesAttended: classesAttended > 0
            ? classesAttended
            : existing.classesAttended,
        attendance: existing.attendance,
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
      classesCount: classesCount,
      classesAttended: classesAttended,
      paidAt: DateTime.now(),
      screenshotPath: path,
    );
    await repo.upsert(created);
    _refresh();
    return created;
  }

  /// Actualiza la asistencia de una semana específica de un pago.
  Future<void> setAttendance(
      int paymentId, DateTime week, int classesTaken) async {
    final repo = _ref.read(paymentRepositoryProvider);
    final p = await repo.getById(paymentId);
    if (p == null) return;
    final updated = p.setAttendance(week, classesTaken);
    await repo.upsert(updated);
    _refresh();
  }

  /// Mueve [classesToMove] clases de [fromWeek] a la siguiente semana
  /// cubierta por el pago. Las clases de la semana origen se reducen
  /// (no pueden quedar negativas) y la semana destino se incrementa.
  /// Útil cuando una persona falta a una semana: las clases quedan
  /// como crédito para la próxima.
  Future<void> moveClassesToNextWeek(
    int paymentId,
    DateTime fromWeek,
    int classesToMove,
  ) async {
    if (classesToMove <= 0) return;
    final repo = _ref.read(paymentRepositoryProvider);
    final p = await repo.getById(paymentId);
    if (p == null) return;
    final settings = _ref.read(settingsSyncProvider);
    final cpw = settings.defaultClassesPerWeek;
    final weeks = p.coveredWeeks(cpw);
    final idx = weeks.indexWhere(
      (w) => w.isAtSameMomentAs(fromWeek),
    );
    if (idx == -1 || idx + 1 >= weeks.length) {
      // No hay semana siguiente cubierta por este pago.
      return;
    }
    final nextWeek = weeks[idx + 1];
    final fromTaken = p.classesTakenIn(fromWeek);
    final move = classesToMove > fromTaken ? fromTaken : classesToMove;
    if (move <= 0) return;
    final updatedFrom = p.setAttendance(fromWeek, fromTaken - move);
    final nextTaken = updatedFrom.classesTakenIn(nextWeek);
    final updated = updatedFrom.setAttendance(nextWeek, nextTaken + move);
    await repo.upsert(updated);
    _refresh();
  }

  /// Quita el pago de un miembro en la semana indicada.
  Future<void> unmarkPaid(int memberId, DateTime weekStart) async {
    final repo = _ref.read(paymentRepositoryProvider);
    final existing = await repo.getForMemberWeek(memberId, weekStart);
    if (existing == null) return;
    await repo.delete(existing.id!);
    _refresh();
  }

  Future<void> updateScreenshot(int paymentId, String? path) async {
    final repo = _ref.read(paymentRepositoryProvider);
    await repo.setScreenshot(paymentId, path);
    _refresh();
  }

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
