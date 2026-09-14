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

/// Calcula el monto a cobrar por N clases usando las tarifas configuradas.
///
/// Regla de negocio:
/// - Si N es par: el monto es `(N/2) × tarifa de 2-clases`
///   (porque las clases vienen de a 2 por el schedule del grupo)
/// - Si N es impar: el monto es `tarifa de 1-clase + ((N-1)/2) × tarifa de 2-clases`
///   (1 clase individual suelta + el resto en pares de 2)
///
/// Ejemplos con tarifa 1-clase = $1.50 y 2-clases = $2.50:
/// - 1 clase  → 0×$2.50 + 1×$1.50 = $1.50
/// - 2 clases → 1×$2.50             = $2.50
/// - 3 clases → 1×$2.50 + 1×$1.50 = $4.00
/// - 8 clases → 4×$2.50             = $10.00
/// - 7 clases → 3×$2.50 + 1×$1.50 = $9.00
double amountForClassCount(int n, AppSettings settings) {
  if (n <= 0) return 0;
  final t1 = settings.amountFor(1) ?? 1.5;
  final t2 = settings.amountFor(2) ?? 2.5;
  if (n.isEven) {
    return (n ~/ 2) * t2;
  } else {
    return t1 + ((n - 1) ~/ 2) * t2;
  }
}

/// Configuración de la app. Las tarifas se persisten en la tabla
/// `app_settings` (DB) o en el mock InMemoryStore (web).
class AppSettings {
  final List<FeeTier> feeTiers;
  final int defaultClassesPerWeek;
  const AppSettings({
    required this.feeTiers,
    this.defaultClassesPerWeek = 2,
  });

  /// Devuelve el monto a cobrar para `classesPerWeek` clases, o null
  /// si no hay una tarifa configurada.
  double? amountFor(int classesPerWeek) {
    for (final t in feeTiers) {
      if (t.classes == classesPerWeek) return t.amount;
    }
    return null;
  }

  /// Tarifa por clase individual. Se usa para calcular el monto a cobrar
  /// cuando no hay una tarifa exacta para la cantidad de clases pedida.
  /// Default: tarifa de 2 clases ÷ 2.
  double get perClassRate {
    final t2 = amountFor(2);
    if (t2 != null) return t2 / 2.0;
    final t1 = amountFor(1);
    if (t1 != null) return t1;
    return 1.5;
  }

  /// La tarifa más común (la de mayor classes) — útil para estimar
  /// "recaudado esperado" sin saber cuántas clases toma cada uno.
  FeeTier get defaultTier =>
      feeTiers.isEmpty ? const FeeTier(classes: 2, amount: 2.5) : feeTiers.first;

  List<FeeTier> get feeTees => feeTiers;

  /// Serializa a Map para guardar en DB.
  Map<String, String> toKeyValueMap() {
    return {
      'fee_tiers': jsonEncode(feeTiers.map((t) => t.toJson()).toList()),
      'default_classes_per_week': defaultClassesPerWeek.toString(),
    };
  }

  factory AppSettings.fromKeyValueMap(Map<String, String> map) {
    final rawTiers = map['fee_tiers'];
    final rawCpw = map['default_classes_per_week'];
    final cpw = int.tryParse(rawCpw ?? '') ?? 2;

    if (rawTiers == null) {
      return AppSettings.defaults().copyWithClassesPerWeek(cpw);
    }
    try {
      final list = jsonDecode(rawTiers) as List<dynamic>;
      final tiers = list
          .map((e) => FeeTier.fromJson(e as Map<String, dynamic>))
          .toList();
      // Ordenar de menor a mayor número de clases.
      tiers.sort((a, b) => a.classes.compareTo(b.classes));
      return AppSettings(feeTiers: tiers, defaultClassesPerWeek: cpw);
    } catch (_) {
      return AppSettings.defaults().copyWithClassesPerWeek(cpw);
    }
  }

  AppSettings copyWith({
    List<FeeTier>? feeTiers,
    int? defaultClassesPerWeek,
  }) {
    return AppSettings(
      feeTiers: feeTiers ?? this.feeTiers,
      defaultClassesPerWeek:
          defaultClassesPerWeek ?? this.defaultClassesPerWeek,
    );
  }

  AppSettings copyWithClassesPerWeek(int cpw) {
    return AppSettings(
      feeTiers: feeTiers,
      defaultClassesPerWeek: cpw,
    );
  }

  factory AppSettings.defaults() => const AppSettings(
        feeTiers: [
          FeeTier(classes: 1, amount: 1.5),
          FeeTier(classes: 2, amount: 2.5),
          FeeTier(classes: 3, amount: 4.0),
        ],
        defaultClassesPerWeek: 2,
      );
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
