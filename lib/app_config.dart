/// Constantes globales de la app Henko. Las tarifas se leen
/// dinámicamente desde [AppSettings] (DB). Acá solo van cosas
/// estáticas que no cambian.
class AppConfig {
  /// AppBar title / brand.
  static const String appName = 'Henko';

  /// Máximo de semanas a mostrar en el selector de historial.
  static const int historyWeeksBack = 8;
}
