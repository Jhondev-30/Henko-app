// Mock de base de datos en memoria para que la app funcione en web.
// En Android/Windows/macOS/Linux se usa SQLite real (path_provider).
// Acá no hay persistencia: los datos viven solo en esta sesión del navegador.

import '../models/member.dart';
import '../models/payment.dart';
import 'settings_repository.dart';

/// Store global en memoria (web-only).
class InMemoryStore {
  InMemoryStore._();
  static final InMemoryStore instance = InMemoryStore._();

  final List<Member> _members = [];
  final List<Payment> _payments = [];
  int _nextMemberId = 1;
  int _nextPaymentId = 1;
  AppSettings _settings = AppSettings.defaults();

  // ── Members ──
  List<Member> membersAll({bool activeOnly = true}) {
    final list = activeOnly
        ? _members.where((m) => m.active).toList()
        : List<Member>.from(_members);
    list.sort((a, b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  int membersCount({bool activeOnly = true}) {
    if (activeOnly) return _members.where((m) => m.active).length;
    return _members.length;
  }

  Future<int> memberInsert(Member m) async {
    final id = _nextMemberId++;
    _members.add(Member(
      id: id,
      name: m.name,
      createdAt: m.createdAt,
      active: m.active,
      photoPath: m.photoPath,
    ));
    return id;
  }

  Future<void> memberUpdatePhoto(int id, String? path) async {
    final i = _members.indexWhere((m) => m.id == id);
    if (i >= 0) {
      final old = _members[i];
      _members[i] = Member(
        id: old.id,
        name: old.name,
        createdAt: old.createdAt,
        active: old.active,
        photoPath: path,
      );
    }
  }

  Future<void> memberSoftDelete(int id) async {
    final i = _members.indexWhere((m) => m.id == id);
    if (i >= 0) {
      _members[i] = _members[i].copyWith(active: false);
    }
  }

  // ── Settings ──
  AppSettings getSettings() => _settings;
  void setSettings(AppSettings s) {
    _settings = s;
  }

  // ── Payments ──
  /// Pagos cuyo rango de semanas cubiertas incluye [weekStart].
  List<Payment> paymentsForWeek(DateTime weekStart) {
    return _payments.where((p) => p.coversWeek(weekStart)).toList();
  }

  Payment? paymentForMemberWeek(int memberId, DateTime weekStart) {
    for (final p in _payments) {
      if (p.memberId == memberId && p.weekStart == weekStart) return p;
    }
    return null;
  }

  /// Pagos que cubren al menos una semana >= [memberId, ...].
  List<Payment> paymentsForMember(int memberId) {
    final list =
        _members.where((m) => m.id == memberId).toList();
    if (list.isEmpty) return const [];
    final pid = list.first.id!;
    final memberPayments = _payments.where((p) => p.memberId == pid).toList();
    memberPayments.sort((a, b) => b.weekStart.compareTo(a.weekStart));
    return memberPayments;
  }

  /// Todos los pagos de un miembro (sin filtro por rango).
  List<Payment> allPaymentsForMember(int memberId) {
    final list = _payments.where((p) => p.memberId == memberId).toList();
    list.sort((a, b) => b.weekStart.compareTo(a.weekStart));
    return list;
  }

  Future<int> paymentUpsert(Payment p) async {
    // Si ya existe un pago que cubre la misma (memberId, weekStart)
    // inicial, lo actualizamos. Si no, lo insertamos.
    final i = _payments.indexWhere(
      (x) => x.memberId == p.memberId && x.weekStart == p.weekStart,
    );
    if (i >= 0) {
      _payments[i] = p;
      return _payments[i].id!;
    }
    final id = _nextPaymentId++;
    _payments.add(Payment(
      id: id,
      memberId: p.memberId,
      weekStart: p.weekStart,
      weekEnd: p.weekEnd,
      amount: p.amount,
      classesAttended: p.classesAttended,
      weeksCovered: p.weeksCovered,
      screenshotPath: p.screenshotPath,
      paidAt: p.paidAt,
      note: p.note,
    ));
    return id;
  }

  Future<int> paymentDelete(int id) async {
    final before = _payments.length;
    _payments.removeWhere((p) => p.id == id);
    return before - _payments.length;
  }

  Future<void> paymentSetScreenshot(int id, String? path) async {
    final i = _payments.indexWhere((p) => p.id == id);
    if (i >= 0) {
      final old = _payments[i];
      _payments[i] = Payment(
        id: old.id,
        memberId: old.memberId,
        weekStart: old.weekStart,
        weekEnd: old.weekEnd,
        amount: old.amount,
        classesAttended: old.classesAttended,
        weeksCovered: old.weeksCovered,
        paidAt: old.paidAt,
        note: old.note,
        screenshotPath: path,
      );
    }
  }

  double totalForWeek(DateTime weekStart) {
    return _payments
        .where((p) => p.coversWeek(weekStart))
        .fold<double>(0, (acc, p) {
      // Para el total de la semana, solo contar la fracción del pago
      // que corresponde a esa semana. Pero como un pago cubre N
      // semanas, lo más simple es: si el pago cubre esta semana, sumar
      // amount / weeksCovered. Para el total real del admin, esto es
      // más fiel.
      final perWeek = p.weeksCovered > 0 ? p.amount / p.weeksCovered : 0;
      return acc + perWeek;
    });
  }

  int countForWeek(DateTime weekStart) {
    return _payments.where((p) => p.coversWeek(weekStart)).length;
  }

  /// Inserta los integrantes del Grupo Henko que falten en la lista
  /// (case-insensitive). Idempotente: si ya están todos, no hace nada.
  void seedDefaultsIfMissing(List<String> names) {
    final existing =
        _members.map((m) => m.name.toLowerCase().trim()).toSet();
    final now = DateTime.now();
    for (final n in names) {
      if (existing.contains(n.toLowerCase().trim())) continue;
      _members.add(Member(
        id: _nextMemberId++,
        name: n,
        createdAt: now,
        active: true,
        photoPath: null,
      ));
    }
  }
}
