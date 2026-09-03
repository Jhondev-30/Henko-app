import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'database.dart';
import 'in_memory_store.dart';

/// Una entrada de tarifa: para N clases por semana, se cobra $X.
class FeeTier {
  final int classes;
  final double amount;
  const FeeTier({required this.classes, required this.amount});

  Map<String, dynamic> toJson() => {'classes': classes, 'amount': amount};
  factory FeeTier.fromJson(Map<String, dynamic> j) => FeeTier(
        classes: j['classes'] as int,
        amount: (j['amount'] as num).toDouble(),
      );
}

/// Configuración de la app. Las tarifas se persisten en la tabla
/// `app_settings` (DB) o en el mock InMemoryStore (web).
class AppSettings {
  final List<FeeTier> feeTiers;
  const AppSettings({required this.feeTiers});

  /// Devuelve el monto a cobrar para `classesPerWeek` clases, o null
  /// si no hay una tarifa configurada.
  double? amountFor(int classesPerWeek) {
    for (final t in feeTiers) {
      if (t.classes == classesPerWeek) return t.amount;
    }
    return null;
  }

  /// La tarifa más común (la de mayor classes) — útil para estimar
  /// "recaudado esperado" sin saber cuántas clases toma cada uno.
  FeeTier get defaultTier =>
      feeTiers.isEmpty ? const FeeTier(classes: 2, amount: 2.5) : feeTees.first;

  List<FeeTier> get feeTees => feeTiers;

  /// Serializa a Map para guardar en DB.
  Map<String, String> toKeyValueMap() {
    return {
      'fee_tiers': jsonEncode(feeTiers.map((t) => t.toJson()).toList()),
    };
  }

  factory AppSettings.fromKeyValueMap(Map<String, String> map) {
    final raw = map['fee_tiers'];
    if (raw == null) return AppSettings.defaults();
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final tiers = list
          .map((e) => FeeTier.fromJson(e as Map<String, dynamic>))
          .toList();
      // Ordenar de menor a mayor número de clases.
      tiers.sort((a, b) => a.classes.compareTo(b.classes));
      return AppSettings(feeTiers: tiers);
    } catch (_) {
      return AppSettings.defaults();
    }
  }

  factory AppSettings.defaults() => const AppSettings(feeTiers: [
        FeeTier(classes: 1, amount: 1.5),
        FeeTier(classes: 2, amount: 2.5),
        FeeTier(classes: 3, amount: 4.0),
      ]);
}

class SettingsRepository {
  final AppDatabase _db;
  SettingsRepository(this._db);

  Future<AppSettings> get() async {
    if (AppDatabase.isWeb) {
      return InMemoryStore.instance.getSettings();
    }
    final db = await _db.database;
    final rows = await db.query('app_settings');
    final map = {for (final r in rows) r['key'] as String: r['value'] as String};
    return AppSettings.fromKeyValueMap(map);
  }

  Future<void> save(AppSettings settings) async {
    if (AppDatabase.isWeb) {
      InMemoryStore.instance.setSettings(settings);
      return;
    }
    final db = await _db.database;
    final map = settings.toKeyValueMap();
    final batch = db.batch();
    for (final entry in map.entries) {
      batch.insert(
        'app_settings',
        {'key': entry.key, 'value': entry.value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
}
