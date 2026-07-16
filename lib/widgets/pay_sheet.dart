import 'package:flutter/material.dart';

import '../models/member.dart';
import '../theme/app_theme.dart';

enum PayAction { withCapture, withoutCapture, cancel }

/// Hoja de acciones cuando el user toca el botón de pago.
///
/// Si el miembro YA está pagado → pregunta si confirma desmarcar
/// (advierte que la captura adjunta se eliminará).
///
/// Si NO está pagado → ofrece opciones para subir captura o marcar
/// sin captura.
class PayActionSheet {
  /// Caso 1: el miembro NO está pagado todavía. Devuelve la acción elegida.
  static Future<PayAction?> showForMarking(BuildContext context, Member member) {
    return showModalBottomSheet<PayAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: _SheetBody(
          title: member.name,
          subtitle: 'Marcar como pagado esta semana',
          icon: Icons.payments_outlined,
          options: const [
            _SheetOption(
              action: PayAction.withCapture,
              icon: Icons.attach_file_rounded,
              title: 'Subir captura y marcar pagado',
              subtitle: 'Adjuntar el capture del pago móvil',
            ),
            _SheetOption(
              action: PayAction.withoutCapture,
              icon: Icons.check_circle_outline_rounded,
              title: 'Solo marcar pagado',
              subtitle: 'Sin captura por ahora — podés subirla después',
            ),
            _SheetOption(
              action: PayAction.cancel,
              icon: Icons.close_rounded,
              title: 'Cancelar',
              subtitle: null,
            ),
          ],
        ),
      ),
    );
  }

  /// Caso 2: el miembro YA está pagado. Si tenía captura, advierte que
  /// se eliminará. Devuelve true si el user confirma desmarcar.
  static Future<bool> showForUnmarking(
    BuildContext context, {
    required String memberName,
    required bool hasCapture,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: hasCapture ? AppTheme.warning : null,
          size: 32,
        ),
        title: const Text('¿Desmarcar pago?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vas a quitar el pago de $memberName en esta semana.',
              style: const TextStyle(fontSize: 14),
            ),
            if (hasCapture) ...[
              const SizedBox(height: 12),
              const _CaptureWarning(),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.error,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Sí, desmarcar'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _SheetBody extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<_SheetOption> options;
  const _SheetBody({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                ),
                child: Icon(icon, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        for (final opt in options) ...[
          ListTile(
            leading: Icon(opt.icon, color: scheme.onSurface),
            title: Text(opt.title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: opt.subtitle == null
                ? null
                : Text(opt.subtitle!,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
            onTap: () => Navigator.pop(context, opt.action),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
          ),
          if (opt != options.last)
            Divider(height: 1, color: scheme.outlineVariant, indent: 64),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SheetOption {
  final PayAction action;
  final IconData icon;
  final String title;
  final String? subtitle;
  const _SheetOption({
    required this.action,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

class _CaptureWarning extends StatelessWidget {
  const _CaptureWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(
          color: AppTheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: const Row(
        children: [
          Icon(Icons.image_not_supported_outlined,
              color: AppTheme.error, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'La captura de pantalla del pago también se eliminará.',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
