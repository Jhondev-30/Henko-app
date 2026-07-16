import 'package:intl/intl.dart';

/// Utilidades para el manejo de semanas (lunes a domingo).
class WeekCalculator {
  /// Devuelve el lunes 00:00:00 de la semana a la que pertenece [date].
  static DateTime weekStart(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    // weekday: Monday = 1 ... Sunday = 7
    final daysFromMonday = d.weekday - 1;
    return d.subtract(Duration(days: daysFromMonday));
  }

  /// Devuelve el domingo 23:59:59 de la semana a la que pertenece [date].
  static DateTime weekEnd(DateTime date) {
    final start = weekStart(date);
    return DateTime(start.year, start.month, start.day, 23, 59, 59)
        .add(const Duration(days: 6));
  }

  /// Lunes 00:00:00 de la semana actual.
  static DateTime currentWeekStart() => weekStart(DateTime.now());

  /// Domingo 23:59:59 de la semana actual.
  static DateTime currentWeekEnd() => weekEnd(DateTime.now());

  /// Días enteros que faltan para que termine la semana actual.
  /// Si es lunes y son las 10am, faltarían 6 días aprox.
  /// Si es domingo, falta < 1 día.
  static int daysRemainingThisWeek() {
    final now = DateTime.now();
    final end = currentWeekEnd();
    final diff = end.difference(now);
    if (diff.isNegative) return 0;
    return diff.inDays;
  }

  /// Devuelve la lista de (weekStart, weekEnd) para las últimas [n] semanas,
  /// ordenadas de más reciente a más antigua.
  static List<({DateTime start, DateTime end})> lastNWeeks(int n) {
    final current = currentWeekStart();
    return List.generate(n, (i) {
      final start = current.subtract(Duration(days: 7 * i));
      final end = DateTime(start.year, start.month, start.day, 23, 59, 59)
          .add(const Duration(days: 6));
      return (start: start, end: end);
    });
  }

  /// Etiqueta amigable para una semana: "Semana del 7 — 13 jul"
  static String label(DateTime start, DateTime end) {
    final fmt = DateFormat('d MMM', 'es');
    return 'Semana ${fmt.format(start)} — ${fmt.format(end)}';
  }

  /// Etiqueta corta: "7 jul"
  static String shortLabel(DateTime date) {
    return DateFormat('d MMM', 'es').format(date);
  }
}
