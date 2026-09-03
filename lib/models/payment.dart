// Modelo de Pago. A partir de v1.3 un solo pago puede cubrir
// múltiples semanas (pago adelantado) y registra cuántas clases
// se tomaron en la semana del pago.
class Payment {
  final int? id;
  final int memberId;

  /// Semana en la que se hizo el pago (lunes).
  /// Para pagos multi-semana, esta es la PRIMERA semana cubierta.
  final DateTime weekStart;

  /// Fin de la semana del pago (domingo).
  final DateTime weekEnd;

  /// Monto total pagado. Puede ser 1.5, 2.5, 4, 10, etc.
  final double amount;

  /// Cantidad de clases que tomó el miembro esa semana (1, 2 o 3+).
  /// Sirve para mostrar en el historial y para calcular el monto
  /// esperado cuando la tarifa es por número de clases.
  final int classesAttended;

  /// Cuántas semanas cubre este pago (>= 1). Por default 1.
  /// Si alguien paga $5 a 2 clases ($2.50/sem) → weeksCovered = 2.
  /// Si alguien paga $10 a 1 clase ($1.50/sem) → weeksCovered = 6.
  final int weeksCovered;

  final String? screenshotPath;
  final DateTime paidAt;
  final String? note;

  const Payment({
    this.id,
    required this.memberId,
    required this.weekStart,
    required this.weekEnd,
    required this.amount,
    this.classesAttended = 2,
    this.weeksCovered = 1,
    this.screenshotPath,
    required this.paidAt,
    this.note,
  });

  /// Devuelve todas las semanas (inicio lunes) que cubre este pago.
  /// Ej: weeksCovered=3 y weekStart=lun 5 → [lun 5, lun 12, lun 19].
  List<DateTime> get coveredWeeks {
    return List<DateTime>.generate(
      weeksCovered,
      (i) => weekStart.add(Duration(days: 7 * i)),
    );
  }

  /// ¿Este pago cubre la semana dada?
  bool coversWeek(DateTime week) {
    return coveredWeeks.any((w) => w.isAtSameMomentAs(week));
  }

  Payment copyWith({
    int? id,
    int? memberId,
    DateTime? weekStart,
    DateTime? weekEnd,
    double? amount,
    int? classesAttended,
    int? weeksCovered,
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
      classesAttended: classesAttended ?? this.classesAttended,
      weeksCovered: weeksCovered ?? this.weeksCovered,
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
      'classes_attended': classesAttended,
      'weeks_covered': weeksCovered,
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
      classesAttended: (map['classes_attended'] as int?) ?? 2,
      weeksCovered: (map['weeks_covered'] as int?) ?? 1,
      screenshotPath: map['screenshot_path'] as String?,
      paidAt: DateTime.fromMillisecondsSinceEpoch(map['paid_at'] as int),
      note: map['note'] as String?,
    );
  }
}
