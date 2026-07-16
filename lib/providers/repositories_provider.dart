import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_config.dart';
import '../data/database.dart';
import '../data/member_repository.dart';
import '../data/payment_repository.dart';

/// Singleton de la base de datos.
final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase.instance;
});

final memberRepositoryProvider = Provider<MemberRepository>((ref) {
  return MemberRepository(ref.watch(databaseProvider));
});

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return PaymentRepository(ref.watch(databaseProvider));
});

/// Cuota semanal fija (configurable desde aquí más adelante).
final weeklyFeeProvider = Provider<double>((ref) => AppConfig.weeklyFee);
