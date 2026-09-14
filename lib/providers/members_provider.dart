import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/default_members.dart';
import '../models/member.dart';
import 'payments_provider.dart';
import 'repositories_provider.dart';

/// Lista de miembros activos. Recargar después de CUD.
final membersProvider = FutureProvider<List<Member>>((ref) async {
  final repo = ref.watch(memberRepositoryProvider);
  // Bootstrap idempotente: usa INSERT OR IGNORE en SQL (DB v4+) para
  // que múltiples ejecuciones concurrentes del provider NO generen
  // duplicados. Es seguro llamarlo cada vez que se monta el provider.
  await repo.insertManyIfMissing(kDefaultMemberNames);
  return repo.getAll();
});

/// Provider mutation helper para refrescar la lista desde cualquier lado.
class MembersNotifier extends StateNotifier<int> {
  final Ref _ref;
  MembersNotifier(this._ref) : super(0);

  Future<int> add(String name, {String? photoPath}) async {
    final repo = _ref.read(memberRepositoryProvider);
    // UPSERT: si el nombre ya existe (aunque esté soft-deleted),
    // lo re-activamos en vez de fallar con UNIQUE constraint.
    final id = await repo.insertOrReactivate(
      name.trim(),
      photoPath: photoPath,
    );
    _ref.invalidate(membersProvider);
    _ref.invalidate(currentWeekStatusProvider);
    _ref.invalidate(currentWeekStatsProvider);
    state = id;
    return id;
  }

  Future<void> rename(int id, String newName) async {
    final repo = _ref.read(memberRepositoryProvider);
    final m = await repo.getById(id);
    if (m == null) return;
    await repo.update(m.copyWith(name: newName.trim()));
    _ref.invalidate(membersProvider);
  }

  Future<void> softDelete(int id) async {
    final repo = _ref.read(memberRepositoryProvider);
    await repo.softDelete(id);
    _ref.invalidate(membersProvider);
    _ref.invalidate(currentWeekStatusProvider);
    _ref.invalidate(currentWeekStatsProvider);
  }
}

final membersNotifierProvider =
    StateNotifierProvider<MembersNotifier, int>((ref) {
  return MembersNotifier(ref);
});
