import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Capa de base de datos. En web usa un mock en memoria (ver
/// [InMemoryStore]); en Android/Windows/etc usa SQLite real.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  /// True si la app está corriendo en web (no hay SQLite nativo).
  static bool get isWeb => kIsWeb;

  Database? _db;

  Future<Database> get database async {
    if (kIsWeb) {
      throw StateError(
        'En web se usa InMemoryStore directamente, no AppDatabase.database.',
      );
    }
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'henko.db');
    return openDatabase(
      path,
      version: 5,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE members (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            active INTEGER NOT NULL DEFAULT 1,
            photo_path TEXT
          );
        ''');
        await db.execute('''
          CREATE TABLE payments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            member_id INTEGER NOT NULL,
            week_start INTEGER NOT NULL,
            week_end INTEGER NOT NULL,
            amount REAL NOT NULL,
            classes_attended INTEGER NOT NULL DEFAULT 2,
            weeks_covered INTEGER NOT NULL DEFAULT 1,
            screenshot_path TEXT,
            paid_at INTEGER NOT NULL,
            note TEXT,
            FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE
          );
        ''');
        await db.execute('''
          CREATE INDEX idx_payments_member_week
            ON payments(member_id, week_start);
        ''');
        await db.execute('''
          CREATE INDEX idx_payments_week
            ON payments(week_start);
        ''');
        await db.execute('''
          CREATE UNIQUE INDEX idx_members_name_unique
            ON members(name COLLATE NOCASE);
        ''');
        await db.execute('''
          CREATE TABLE app_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          );
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE members ADD COLUMN photo_path TEXT',
          );
        }
        if (oldVersion < 3) {
          await db.delete('members');
        }
        if (oldVersion < 4) {
          await db.execute('''
            DELETE FROM members
            WHERE id NOT IN (
              SELECT MIN(id) FROM members GROUP BY name COLLATE NOCASE
            )
          ''');
          await db.execute('''
            CREATE UNIQUE INDEX IF NOT EXISTS idx_members_name_unique
              ON members(name COLLATE NOCASE);
          ''');
        }
        if (oldVersion < 5) {
          // v1.3.0: tarifas editables + pagos multi-semana.
          await db.execute(
            "ALTER TABLE payments ADD COLUMN classes_attended INTEGER NOT NULL DEFAULT 2",
          );
          await db.execute(
            "ALTER TABLE payments ADD COLUMN weeks_covered INTEGER NOT NULL DEFAULT 1",
          );
          await db.execute('''
            CREATE TABLE IF NOT EXISTS app_settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            );
          ''');
        }
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
