import 'package:sqflite/sqflite.dart';

import '../models/member.dart';
import 'database.dart';
import 'in_memory_store.dart';

class MemberRepository {
  final AppDatabase _db;
  MemberRepository(this._db);

  Future<List<Member>> getAll({bool activeOnly = true}) async {
    if (AppDatabase.isWeb) {
      return InMemoryStore.instance.membersAll(activeOnly: activeOnly);
    }
    final db = await _db.database;
    final rows = await db.query(
      'members',
      where: activeOnly ? 'active = ?' : null,
      whereArgs: activeOnly ? [1] : null,
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Member.fromMap).toList();
  }

  Future<Member?> getById(int id) async {
    if (AppDatabase.isWeb) {
      final list = InMemoryStore.instance.membersAll(activeOnly: false);
      for (final m in list) {
        if (m.id == id) return m;
      }
      return null;
    }
    final db = await _db.database;
    final rows = await db.query(
      'members',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Member.fromMap(rows.first);
  }

  Future<int> insert(Member member) async {
    if (AppDatabase.isWeb) {
      return InMemoryStore.instance.memberInsert(member);
    }
    final db = await _db.database;
    final data = Map<String, dynamic>.from(member.toMap())..remove('id');
    return db.insert('members', data);
  }

  Future<int> update(Member member) async {
    if (AppDatabase.isWeb) {
      // Para web (mock) no usamos update masivo, solo actualizamos la lista.
      return 0;
    }
    final db = await _db.database;
    return db.update(
      'members',
      member.toMap(),
      where: 'id = ?',
      whereArgs: [member.id],
    );
  }

  /// Actualiza solo la foto del miembro (evita tocar los demás campos).
  Future<void> updatePhoto(int id, String? path) async {
    if (AppDatabase.isWeb) {
      await InMemoryStore.instance.memberUpdatePhoto(id, path);
      return;
    }
    final db = await _db.database;
    await db.update(
      'members',
      {'photo_path': path},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> softDelete(int id) async {
    if (AppDatabase.isWeb) {
      await InMemoryStore.instance.memberSoftDelete(id);
      return 1;
    }
    final db = await _db.database;
    return db.update(
      'members',
      {'active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> count({bool activeOnly = true}) async {
    if (AppDatabase.isWeb) {
      return InMemoryStore.instance.membersCount(activeOnly: activeOnly);
    }
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM members ${activeOnly ? 'WHERE active = 1' : ''}',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Inserta varios miembros de una sola vez (usado para seed/demo).
  Future<void> insertMany(List<String> names) async {
    if (AppDatabase.isWeb) {
      for (final n in names) {
        await InMemoryStore.instance.memberInsert(
          Member(name: n, createdAt: DateTime.now()),
        );
      }
      return;
    }
    final db = await _db.database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final name in names) {
      batch.insert('members', {
        'name': name,
        'created_at': now,
        'active': 1,
      });
    }
    await batch.commit(noResult: true);
  }

  /// Versión idempotente de insertMany: usa INSERT OR IGNORE para que
  /// múltiples llamadas concurrentes no generen duplicados. Requiere el
  /// UNIQUE INDEX idx_members_name_unique en members.name (DB v4+).
  ///
  /// Si el nombre ya existe (case-insensitive), se ignora silenciosamente.
  Future<void> insertManyIfMissing(List<String> names) async {
    if (AppDatabase.isWeb) {
      InMemoryStore.instance.seedDefaultsIfMissing(names);
      return;
    }
    final db = await _db.database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final name in names) {
      batch.rawInsert(
        '''
        INSERT OR IGNORE INTO members (name, created_at, active)
        VALUES (?, ?, 1)
        ''',
        [name, now],
      );
    }
    await batch.commit(noResult: true);
  }
}
