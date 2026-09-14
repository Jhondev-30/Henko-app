import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/member.dart';
import '../models/payment.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../utils/currency_formatter.dart';

/// Card de un miembro en la lista — Material 3 con elevación sutil.
class MemberTile extends ConsumerWidget {
  final Member member;
  final Payment? payment;
  final VoidCallback onTapPayButton;
  final VoidCallback? onTap;

  const MemberTile({
    super.key,
    required this.member,
    required this.payment,
    required this.onTapPayButton,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPaid = payment != null;
    final hasPhoto = member.photoPath != null && member.photoPath!.isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    // Necesitamos el classesPerWeek actual para calcular la fracción
    // per-semana cuando el pago cubre varias semanas.
    final cpw = ref.watch(settingsSyncProvider).defaultClassesPerWeek;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.white,
        elevation: 0,
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(AppTheme.rLg),
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _Avatar(member: member, hasPhoto: hasPhoto),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        member.name,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      _StatusPill(
                        hasPaid: hasPaid,
                        payment: payment,
                        classesPerWeek: cpw,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _PayButton(paid: hasPaid, onPressed: onTapPayButton),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool hasPaid;
  final Payment? payment;
  final int classesPerWeek;
  const _StatusPill({
    required this.hasPaid,
    required this.payment,
    required this.classesPerWeek,
  });

  @override
  Widget build(BuildContext context) {
    if (hasPaid) {
      // Fracción per-semana del pago (cuánto aporta ESTA semana).
      // Pago multi-semana (ej: $10 / 8 clases / 2 clases-sem = 4 sem)
      // → muestra $2.50 esta semana + badge "cubre 4 sem (8 clases)".
      final weeksCovered = classesPerWeek <= 0
          ? 1
          : (payment!.classesCount / classesPerWeek).floor().clamp(1, 99);
      final perWeek = weeksCovered == 0
          ? payment!.amount
          : payment!.amount / weeksCovered;
      final isMultiWeek = weeksCovered > 1;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTheme.rFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_rounded,
                size: 12, color: AppTheme.success),
            const SizedBox(width: 4),
            Text(
              'Pagó ${CurrencyFormatter.format(perWeek)}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.success,
              ),
            ),
            if (isMultiWeek) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppTheme.rFull),
                ),
                child: Text(
                  'cubre $weeksCovered sem (${payment!.classesCount} clases)',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.success,
                  ),
                ),
              ),
            ],
            if (payment!.screenshotPath != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.attachment_rounded,
                  size: 11, color: AppTheme.success),
            ],
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.rFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppTheme.error,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'Pendiente',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final Member member;
  final bool hasPhoto;
  const _Avatar({required this.member, required this.hasPhoto});

  String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget child;
    if (hasPhoto) {
      child = _buildPhotoImage(member.photoPath!);
    } else {
      child = Container(
        color: scheme.secondaryContainer,
        alignment: Alignment.center,
        child: Text(
          _initials(member.name),
          style: TextStyle(
            color: scheme.onSecondaryContainer,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      );
    }
    return ClipOval(
      child: SizedBox(
        width: 44,
        height: 44,
        child: child,
      ),
    );
  }

  Widget _buildPhotoImage(String path) {
    if (path.startsWith('data:')) {
      try {
        final b64 = path.split(',').last;
        return Image.memory(
          base64Decode(b64),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        );
      } catch (_) {
        return _placeholder();
      }
    }
    if (path.startsWith('blob:') || path.startsWith('http')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return Container(color: Colors.grey.shade300);
  }
}

class _PayButton extends StatelessWidget {
  final bool paid;
  final VoidCallback onPressed;
  const _PayButton({required this.paid, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: paid ? 'Desmarcar pago' : 'Marcar como pagado',
      button: true,
      child: InkResponse(
        onTap: onPressed,
        radius: 28,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: paid
                ? AppTheme.success
                : Colors.white,
            shape: BoxShape.circle,
            border: paid
                ? null
                : Border.all(
                    color: Theme.of(context).colorScheme.outline,
                    width: 1.5,
                  ),
            boxShadow: paid
                ? [
                    BoxShadow(
                      color: AppTheme.success.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            paid ? Icons.check_rounded : Icons.payments_outlined,
            color: paid ? Colors.white : Theme.of(context).colorScheme.primary,
            size: 20,
          ),
        ),
      ),
    );
  }
}
