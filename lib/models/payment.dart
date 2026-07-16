// Modelo de Pago semanal
class Payment {
  final int? id;
  final int memberId;
  // Semana del pago (lunes a domingo)
  final DateTime weekStart;
  final DateTime weekEnd;
  final double amount;
  final String? screenshotPath;
  final DateTime paidAt;
  final String? note;

  const Payment({
    this.id,
    required this.memberId,
    required this.weekStart,
    required this.weekEnd,
    required this.amount,
    this.screenshotPath,
    required this.paidAt,
    this.note,
  });

  Payment copyWith({
    int? id,
    int? memberId,
    DateTime? weekStart,
    DateTime? weekEnd,
    double? amount,
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
      screenshotPath: map['screenshot_path'] as String?,
      paidAt: DateTime.fromMillisecondsSinceEpoch(map['paid_at'] as int),
      note: map['note'] as String?,
    );
  }
}
