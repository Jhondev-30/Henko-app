import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/member.dart';
import '../models/payment.dart';
import 'members_provider.dart';
import 'payments_provider.dart';

/// Item de la lista del Home: miembro + su pago de esta semana (si existe).
class MemberWithStatus {
  final Member member;
  final Payment? payment;
  const MemberWithStatus({required this.member, this.payment});
  bool get hasPaid => payment != null;
}

/// Lista combinada de miembros con su estado de pago de la semana actual.
final membersWithStatusProvider =
    FutureProvider<List<MemberWithStatus>>((ref) async {
  final members = await ref.watch(membersProvider.future);
  final payments = await ref.watch(currentWeekPaymentsProvider.future);
  final byMember = {for (final p in payments) p.memberId: p};
  return members
      .map((m) => MemberWithStatus(member: m, payment: byMember[m.id]))
      .toList();
});
