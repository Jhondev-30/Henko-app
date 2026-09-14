import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import '../models/payment.dart';
import 'database.dart';
import 'in_memory_store.dart';

class PaymentRepository {
  final AppDatabase _db;
  PaymentRepository(this._db);

  /// Devuelve el pago MÁS RECIENTE del miembro que arranca en [weekStart].
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

  /// Devuelve un pago por su ID.
  Future<Payment?> getById(int id) async {
    if (AppDatabase.isWeb) {
      for (final p in InMemoryStore.instance.allPaymentsForMember(0)) {
        if (p.id == id) return p;
      }
      // Búsqueda amplia: recorremos todos los miembros
      for (final m in InMemoryStore.instance.membersAll(activeOnly: false)) {
        if (m.id == null) continue;
        for (final p in InMemoryStore.instance.allPaymentsForMember(m.id!)) {
          if (p.id == id) return p;
        }
      }
      return null;
    }
    final db = await _db.database;
    final rows = await db.query('payments', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Payment.fromMap(rows.first);
  }

  /// Pagos que cubren [weekStart] según la cantidad de clases y
  /// `classesPerWeek` actual.
  Future<List<Payment>> getForWeek(
      DateTime weekStart, int classesPerWeek) async {
    if (AppDatabase.isWeb) {
      return InMemoryStore.instance
          .paymentsForWeek(weekStart, classesPerWeek);
    }
    final db = await _db.database;
    final rows = await db.query(
      'payments',
      where: 'week_start <= ?',
      whereArgs: [weekStart.millisecondsSinceEpoch],
      orderBy: 'paid_at ASC',
    );
    final payments = rows.map(Payment.fromMap).toList();
    return payments
        .where((p) => p.coversWeek(weekStart, classesPerWeek))
        .toList();
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

  /// Borra TODOS los pagos de un miembro.
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

  /// Total REAL de la semana: por cada pago, clases tomadas esa semana
  /// × tarifa-por-clase **de ese mismo pago** (amount/classesCount).
  ///
  /// Cada pago tiene su propia tarifa porque los pagos pueden ser de
  /// montos distintos. Ej: Aynara $10/8 clases = $1.25/clase, Annah
  /// $7.50/6 clases = $1.25/clase, pero podrían ser distintos.
  Future<double> totalForWeek(
      DateTime weekStart, int classesPerWeek) async {
    final payments = await getForWeek(weekStart, classesPerWeek);
    return payments.fold<double>(0, (acc, p) {
      if (p.classesCount <= 0) return acc;
      final perClass = p.amount / p.classesCount;
      // Clases tomadas esa semana (puede ser 0 si la persona faltó).
      final taken = p.classesTakenIn(weekStart);
      return acc + taken * perClass;
    });
  }

  Future<int> countForWeek(
      DateTime weekStart, int classesPerWeek) async {
    final payments = await getForWeek(weekStart, classesPerWeek);
    return payments.length;
  }
}
