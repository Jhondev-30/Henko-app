import 'package:sqflite/sqflite.dart';

import '../models/payment.dart';
import 'database.dart';
import 'in_memory_store.dart';

class PaymentRepository {
  final AppDatabase _db;
  PaymentRepository(this._db);

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

  Future<List<Payment>> getForWeek(DateTime weekStart) async {
    if (AppDatabase.isWeb) {
      return InMemoryStore.instance.paymentsForWeek(weekStart);
    }
    final db = await _db.database;
    final rows = await db.query(
      'payments',
      where: 'week_start = ?',
      whereArgs: [weekStart.millisecondsSinceEpoch],
      orderBy: 'paid_at ASC',
    );
    return rows.map(Payment.fromMap).toList();
  }

  Future<List<Payment>> getForMember(int memberId) async {
    if (AppDatabase.isWeb) {
      return InMemoryStore.instance.paymentsForMember(memberId);
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

  Future<double> totalForWeek(DateTime weekStart) async {
    if (AppDatabase.isWeb) {
      return InMemoryStore.instance.totalForWeek(weekStart);
    }
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM payments WHERE week_start = ?',
      [weekStart.millisecondsSinceEpoch],
    );
    return (result.first['total'] as num).toDouble();
  }

  Future<int> countForWeek(DateTime weekStart) async {
    if (AppDatabase.isWeb) {
      return InMemoryStore.instance.countForWeek(weekStart);
    }
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM payments WHERE week_start = ?',
      [weekStart.millisecondsSinceEpoch],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
