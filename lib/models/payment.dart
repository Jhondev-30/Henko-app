// Modelo de Pago. La unidad de cuenta son CLASES, no semanas.
// Un pago de N clases cubre N / classesPerWeek semanas.
// Ej: 4 clases a 2 clases/sem = cubre 2 semanas.
class Payment {
  final int? id;
  final int memberId;

  /// Semana en la que se hizo el pago (lunes).
  /// Para pagos multi-semana, esta es la PRIMERA semana cubierta.
  final DateTime weekStart;

  /// Fin de la semana del pago (domingo).
  final DateTime weekEnd;

  /// Monto total pagado en dinero. Lo que el admin recibió.
  final double amount;

  /// Total de clases que cubre este pago. Por ejemplo:
  /// - 1 clase para una sola clase suelta
  /// - 2 clases para una semana completa
  /// - 4 clases para dos semanas (2 clases/sem × 2)
  /// - 6 clases para tres semanas, etc.
  final int classesCount;

  /// Cuántas clases tomó el miembro efectivamente en la semana del pago.
  /// Por default es igual a classesPerWeek vigente al momento del pago.
  /// El admin puede editar esto después si la persona faltó.
  final int classesAttended;

  /// Cuántas clases tomó el miembro en cada semana cubierta.
  /// La clave es la semana (lunes) y el valor es la cantidad de clases
  /// que tomó en esa semana. Una clase no tomada genera "crédito"
  /// que se descuenta del total.
  /// Si está vacío, se asume que tomó classesPerWeek clases por semana.
  final Map<String, int> attendance;

  final String? screenshotPath;
  final DateTime paidAt;
  final String? note;

  const Payment({
    this.id,
    required this.memberId,
    required this.weekStart,
    required this.weekEnd,
    required this.amount,
    required this.classesCount,
    this.classesAttended = 0,
    this.attendance = const {},
    this.screenshotPath,
    required this.paidAt,
    this.note,
  });

  /// Devuelve las semanas (inicio lunes) que cubre este pago según
  /// la cantidad de clases y el `classesPerWeek` dado.
  List<DateTime> coveredWeeks(int classesPerWeek) {
    if (classesPerWeek <= 0) return [weekStart];
    final weeks = (classesCount / classesPerWeek).floor();
    final n = weeks < 1 ? 1 : weeks;
    return List<DateTime>.generate(
      n,
      (i) => weekStart.add(Duration(days: 7 * i)),
    );
  }

  /// ¿Este pago cubre la semana dada, según el classesPerWeek actual?
  bool coversWeek(DateTime week, int classesPerWeek) {
    return coveredWeeks(classesPerWeek).any((w) => w.isAtSameMomentAs(week));
  }

  /// Cuántas clases tomó en la semana dada (o 0 si no se especificó).
  int classesTakenIn(DateTime week) {
    final key = week.millisecondsSinceEpoch.toString();
    return attendance[key] ?? classesAttended;
  }

  /// Devuelve un Payment con la asistencia de una semana específica
  /// actualizada.
  Payment setAttendance(DateTime week, int classesTaken) {
    final newMap = Map<String, int>.from(attendance);
    final key = week.millisecondsSinceEpoch.toString();
    newMap[key] = classesTaken;
    return copyWith(attendance: newMap);
  }

  Payment copyWith({
    int? id,
    int? memberId,
    DateTime? weekStart,
    DateTime? weekEnd,
    double? amount,
    int? classesCount,
    int? classesAttended,
    Map<String, int>? attendance,
    String? screenshotPath,
    DateTime? paidAt,
    String? note,
  }) {
    return Payment(
      id: id ?? this.id,
      memberId: memberId ?? this.memberId,
      weekStart: weekStart ?? this.weekStart,
      weekEnd: weekEnd ?? this.weekEnd,
      amount: amount ?? this.amount,
      classesCount: classesCount ?? this.classesCount,
      classesAttended: classesAttended ?? this.classesAttended,
      attendance: attendance ?? this.attendance,
      screenshotPath: screenshotPath ?? this.screenshotPath,
      paidAt: paidAt ?? this.paidAt,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'member_id': memberId,
      'week_start': weekStart.millisecondsSinceEpoch,
      'week_end': weekEnd.millisecondsSinceEpoch,
      'amount': amount,
      'classes_count': classesCount,
      'classes_attended': classesAttended,
      'attendance': _encodeAttendance(attendance),
      'screenshot_path': screenshotPath,
      'paid_at': paidAt.millisecondsSinceEpoch,
      'note': note,
    };
  }

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      id: map['id'] as int?,
      memberId: map['member_id'] as int,
      weekStart:
          DateTime.fromMillisecondsSinceEpoch(map['week_start'] as int),
      weekEnd:
          DateTime.fromMillisecondsSinceEpoch(map['week_end'] as int),
      amount: (map['amount'] as num).toDouble(),
      classesCount: (map['classes_count'] as int?) ?? 1,
      classesAttended: (map['classes_attended'] as int?) ?? 0,
      attendance: _decodeAttendance(
          map['attendance'] as String? ?? ''),
      screenshotPath: map['screenshot_path'] as String?,
      paidAt: DateTime.fromMillisecondsSinceEpoch(map['paid_at'] as int),
      note: map['note'] as String?,
    );
  }

  static String _encodeAttendance(Map<String, int> a) {
    if (a.isEmpty) return '';
    return a.entries.map((e) => '${e.key}:${e.value}').join(',');
  }

  static Map<String, int> _decodeAttendance(String raw) {
    if (raw.isEmpty) return {};
    final map = <String, int>{};
    for (final pair in raw.split(',')) {
      final i = pair.indexOf(':');
      if (i > 0) {
        final k = pair.substring(0, i);
        final v = int.tryParse(pair.substring(i + 1));
        if (v != null) map[k] = v;
      }
    }
    return map;
  }
}
