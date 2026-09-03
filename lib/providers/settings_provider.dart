import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_repository.dart';
import 'repositories_provider.dart';

/// Configuración actual de la app (tarifas, etc.).
final settingsProvider = FutureProvider<AppSettings>((ref) async {
  return ref.watch(settingsRepositoryProvider).get();
});

/// Versión síncrona: si ya está cargada, úsala; si no, devuelve defaults.
final settingsSyncProvider = Provider<AppSettings>((ref) {
  final s = ref.watch(settingsProvider);
  return s.valueOrNull ?? AppSettings.defaults();
});
