import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import '../models/payment.dart';
import 'database.dart';
import 'in_memory_store.dart';

class PaymentRepository {
  final AppDatabase _db;
  PaymentRepository(this._db);

  /// Devuelve el pago MÁS RECIENTE del miembro que cubre [weekStart].
  /// Útil para preguntar "¿tiene pago esta semana?".
  Future<Payment?> getForMemberWeek(
      int memberId, DateTime weekStart) async {
    if (AppDatabase.isWeb) {
      return InMemoryStore.instance
          .paymentForMemberWeek(memberId, weekStart);
    }
    final db = await _db.database;
    final rows = await db.query(
      'payments',
      where: 'member_id = ? AND week_start = ?',
      whereArgs: [memberId, weekStart.millisecondsSinceEpoch],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Payment.fromMap(rows.first);
  }

  /// Pagos que cubren [weekStart] (puede ser un pago multi-semana).
  /// IMPORTANTE: para un pago con weeksCovered=3 y weekStart=lun 5,
  /// este método lo devuelve para lun 5, lun 12 y lun 19.
  Future<List<Payment>> getForWeek(DateTime weekStart) async {
    if (AppDatabase.isWeb) {
      return InMemoryStore.instance.paymentsForWeek(weekStart);
    }
    final db = await _db.database;
    // Buscamos pagos cuyo weekStart <= weekStart < weekStart + 7*N días
    // Equivalente SQL: week_start <= X AND week_start + weeks_covered*7 > X
    final target = weekStart.millisecondsSinceEpoch;
    final weekMs = 7 * 24 * 60 * 60 * 1000;
    final rows = await db.rawQuery('''
      SELECT * FROM payments
      WHERE week_start <= ?
        AND (week_start + weeks_covered * ?) > ?
      ORDER BY paid_at ASC
    ''', [target, weekMs, target]);
    return rows.map(Payment.fromMap).toList();
  }

  Future<List<Payment>> getForMember(int memberId) async {
    if (AppDatabase.isWeb) {
      return InMemoryStore.instance.allPaymentsForMember(memberId);
    }
    final db = await _db.database;
    final rows = await db.query(
      'payments',
      where: 'member_id = ?',
      whereArgs: [memberId],
      orderBy: 'week_start DESC',
    );
    return rows.map(Payment.fromMap).toList();
  }

  /// Devuelve TODOS los pagos (sin filtro). Usado por el backup.
  Future<List<Payment>> getAllPaymentsForBackup() async {
    if (AppDatabase.isWeb) {
      // En web el store tiene todo en memoria
      final list = <Payment>[];
      for (final m in InMemoryStore.instance.membersAll(activeOnly: false)) {
        if (m.id == null) continue;
        list.addAll(
          InMemoryStore.instance.allPaymentsForMember(m.id!),
        );
      }
      return list;
    }
    final db = await _db.database;
    final rows = await db.query('payments', orderBy: 'week_start DESC');
    return rows.map(Payment.fromMap).toList();
  }

  Future<int> upsert(Payment payment) async {
    if (AppDatabase.isWeb) {
      return InMemoryStore.instance.paymentUpsert(payment);
    }
    final db = await _db.database;
    final existing = await db.query(
      'payments',
      where: 'member_id = ? AND week_start = ?',
      whereArgs: [
        payment.memberId,
        payment.weekStart.millisecondsSinceEpoch,
      ],
      limit: 1,
    );
    if (existing.isEmpty) {
      final data = Map<String, dynamic>.from(payment.toMap())..remove('id');
      return db.insert('payments', data);
    } else {
      return db.update(
        'payments',
        payment.toMap(),
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  Future<int> delete(int id) async {
    if (AppDatabase.isWeb) {
      return InMemoryStore.instance.paymentDelete(id);
    }
    final db = await _db.database;
    return db.delete('payments', where: 'id = ?', whereArgs: [id]);
  }

  /// Borra TODOS los pagos de un miembro. Útil para corregir
  /// pagos mal registrados.
  Future<int> deleteAllForMember(int memberId) async {
    if (AppDatabase.isWeb) {
      int count = 0;
      for (final p in InMemoryStore.instance.allPaymentsForMember(memberId)) {
        if (p.id != null) {
          await InMemoryStore.instance.paymentDelete(p.id!);
          count++;
        }
      }
      return count;
    }
    final db = await _db.database;
    return db.delete('payments', where: 'member_id = ?', whereArgs: [memberId]);
  }

  Future<void> setScreenshot(int id, String? path) async {
    if (AppDatabase.isWeb) {
      await InMemoryStore.instance.paymentSetScreenshot(id, path);
      return;
    }
    final db = await _db.database;
    await db.update(
      'payments',
      {'screenshot_path': path},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Total real de la semana (sumando la fracción de pagos multi-semana
  /// que corresponde a esta semana).
  Future<double> totalForWeek(DateTime weekStart) async {
    final payments = await getForWeek(weekStart);
    return payments.fold<double>(0, (acc, p) {
      final perWeek = p.weeksCovered > 0 ? p.amount / p.weeksCovered : 0;
      return acc + perWeek;
    });
  }

  Future<int> countForWeek(DateTime weekStart) async {
    final payments = await getForWeek(weekStart);
    return payments.length;
  }
}
