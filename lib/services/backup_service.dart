import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../data/database.dart';
import '../data/member_repository.dart';
import '../data/payment_repository.dart';
import '../data/settings_repository.dart';

/// Estructura del backup JSON. Es estable: cualquier versión de la
/// app puede leer un backup de otra versión (mientras los campos
/// existan).
class HenkoBackup {
  final int version;
  final DateTime exportedAt;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> payments;
  final Map<String, String> settings;
  final String? source;

  const HenkoBackup({
    required this.version,
    required this.exportedAt,
    required this.members,
    required this.payments,
    required this.settings,
    this.source,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'exported_at': exportedAt.toIso8601String(),
        'source': source ?? 'henko',
        'members': members,
        'payments': payments,
        'settings': settings,
      };

  String toJsonString() =>
      const JsonEncoder.withIndent('  ').convert(toJson());

  factory HenkoBackup.fromJsonString(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return HenkoBackup(
      version: (map['version'] as int?) ?? 1,
      exportedAt: DateTime.tryParse(map['exported_at'] as String? ?? '') ??
          DateTime.now(),
      members: (map['members'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      payments: (map['payments'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      settings: (map['settings'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
      source: map['source'] as String?,
    );
  }
}

/// Servicio para exportar e importar la base de datos completa.
class BackupService {
  final AppDatabase db;
  final MemberRepository memberRepo;
  final PaymentRepository paymentRepo;
  final SettingsRepository settingsRepo;

  BackupService({
    required this.db,
    required this.memberRepo,
    required this.paymentRepo,
    required this.settingsRepo,
  });

  /// Construye un backup con todos los datos actuales.
  Future<HenkoBackup> buildBackup() async {
    final members = await memberRepo.getAll(activeOnly: false);
    final payments = await paymentRepo.getAllPaymentsForBackup();
    final settings = await settingsRepo.get();
    return HenkoBackup(
      version: 1,
      exportedAt: DateTime.now(),
      members: members.map((m) => m.toMap()).toList(),
      payments: payments.map((p) => p.toMap()).toList(),
      settings: settings.toKeyValueMap(),
    );
  }

  /// Exporta el backup a un archivo JSON en el directorio temporal
  /// y devuelve la ruta. El archivo se llama henko-backup-YYYYMMDD-HHmmss.json
  Future<String> exportToFile() async {
    if (kIsWeb) {
      throw UnsupportedError('Exportar a archivo no está disponible en web.');
    }
    final backup = await buildBackup();
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-')
        .substring(0, 19);
    final path = p.join(dir.path, 'henko-backup-$ts.json');
    final file = File(path);
    await file.writeAsString(backup.toJsonString());
    return path;
  }

  /// Importa un backup desde un JSON string. REEMPLAZA todos los
  /// datos existentes. Usar con cuidado.
  Future<void> importFromJsonString(String raw) async {
    if (kIsWeb) {
      throw UnsupportedError('Importar desde archivo no está disponible en web.');
    }
    final backup = HenkoBackup.fromJsonString(raw);
    final database = await db.database;
    final batch = database.batch();
    // Limpiar tablas actuales
    batch.delete('payments');
    batch.delete('members');
    // Insertar miembros
    for (final m in backup.members) {
      final data = Map<String, dynamic>.from(m)..remove('id');
      // Asignar nuevos IDs para evitar conflictos
      batch.insert('members', data);
    }
    await batch.commit(noResult: true);

    final batch2 = database.batch();
    for (final p in backup.payments) {
      final data = Map<String, dynamic>.from(p)..remove('id');
      batch2.insert('payments', data);
    }
    // Settings: insertar o reemplazar
    for (final entry in backup.settings.entries) {
      batch2.insert(
        'app_settings',
        {'key': entry.key, 'value': entry.value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch2.commit(noResult: true);
  }
}
