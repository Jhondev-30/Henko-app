import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/payment.dart';
import '../providers/home_providers.dart';
import '../providers/payments_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../utils/week_calculator.dart';

/// Genera un mensaje de recordatorio de pago semanal para enviar por
/// WhatsApp o copiar al portapapeles.
class ReminderMessageBuilder {
  static String build({
    required List<({
      String name,
      bool paid,
      double? amount,
      int? classesCount,
      int classesPerWeek,
    })> rows,
    required double totalCollected,
    required double expected,
    required int paidCount,
    required int totalCount,
    required DateTime weekStart,
    required DateTime weekEnd,
    required String feeDescription,
  }) {
    final weekLabel = WeekCalculator.label(weekStart, weekEnd);
    final pendientes = rows.where((r) => !r.paid).map((r) => r.name).toList();
    final fmt = NumberFormat.currency(
      locale: 'en_US',
      symbol: r'\$',
      decimalDigits: 2,
    );

    // "Ya aportaron" muestra el APORTE INDIVIDUAL de esta semana, no el
    // monto total del pago. Para pagos multi-semana se desglosa.
    String lineFor(RowAccessor r) {
      final n = r.name;
      final classesCount = r.classesCount;
      if (classesCount == null || classesCount <= 0) {
        return '• $n';
      }
      final weeksCovered = (classesCount / r.classesPerWeek).floor();
      final effectiveWeeks = weeksCovered < 1 ? 1 : weeksCovered;
      // Fracción per-semana del pago total.
      final amount = r.amount ?? 0.0;
      final perWeek = amount / effectiveWeeks;
      if (effectiveWeeks > 1) {
        return '• $n — ${fmt.format(perWeek)} esta semana '
            '(pagó ${fmt.format(amount)} / $effectiveWeeks sem)';
      }
      return '• $n — ${fmt.format(perWeek)}';
    }

    final pagaron = rows.where((r) => r.paid).toList();
    final pendientesTxt = pendientes.isEmpty
        ? '_¡Todos al día! Gracias por la disciplina del grupo._'
        : pendientes.map((n) => '• $n').join('\n');
    final pagaronTxt = pagaron.isEmpty
        ? '_Aún nadie ha confirmado su aporte._'
        : pagaron.map(lineFor).join('\n');

    final buffer = StringBuffer()
      ..writeln('💃 *HENKO* — _Grupo Estable de Danza Contemporánea_')
      ..writeln('*Recordatorio de aporte semanal*')
      ..writeln('Semana: $weekLabel')
      ..writeln('')
      ..writeln(
        '✅ *Recaudado:* ${fmt.format(totalCollected)} '
        'de ${fmt.format(expected)}',
      )
      ..writeln('👥 *Pagaron:* $paidCount de $totalCount')
      ..writeln('')
      ..writeln('*Ya aportaron 🙌*')
      ..writeln(pagaronTxt)
      ..writeln('')
      ..writeln('*Faltan por aportar 💸*')
      ..writeln(pendientesTxt)
      ..writeln('')
      ..writeln('Las tarifas son: $feeDescription.')
      ..writeln('')
      ..writeln(
        '_«Transformamos el movimiento en arte, y el compromiso '
        'en comunidad.»_',
      );

    return buffer.toString();
  }
}

/// Tipo alias para los rows (compatible con `({...})` records de Dart 3).
typedef RowAccessor = ({
  String name,
  bool paid,
  double? amount,
  int? classesCount,
  int classesPerWeek,
});

/// Hoja inferior con dos acciones: copiar al portapapeles o abrir WhatsApp.
class ReminderSheet {
  /// Muestra el sheet de recordatorio. `onResult` recibe el mensaje armado
  /// (útil si la pantalla padre quiere mostrar un snackbar).
  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    void Function(String message)? onResult,
  }) async {
    final selectedWeek = ref.read(selectedWeekStartProvider);
    final weekEnd = WeekCalculator.weekEnd(selectedWeek);
    final membersAsync = ref.read(membersWithStatusProvider);

    final members = membersAsync.valueOrNull;
    if (members == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cargando datos, intenta de nuevo…')),
      );
      return;
    }

    final paidIds = {
      for (final p in ref.read(currentWeekPaymentsProvider).valueOrNull ??
          <Payment>[])
        p.memberId: p,
    };

    final settings = ref.read(settingsSyncProvider);
    final cpw = settings.defaultClassesPerWeek;

    final rows = members
        .map((m) => (
              name: m.member.name,
              paid: m.payment != null,
              amount: m.payment?.amount,
              classesCount: m.payment?.classesCount,
              classesPerWeek: cpw,
            ))
        .toList();
    final paidCount = rows.where((r) => r.paid).length;
    // Total REAL: por cada pago, clases tomadas esa semana × tarifa
    // per-clase de ESE pago. Antes se usaba la tarifa global y se sumaba
    // el monto completo de pagos multi-semana (bug v1.5.1).
    final totalCollected = paidIds.values.fold<double>(0, (acc, p) {
      if (p.classesCount <= 0) return acc;
      final perClass = p.amount / p.classesCount;
      final taken = p.classesTakenIn(selectedWeek);
      return acc + taken * perClass;
    });
    final perClassRate = settings.perClassRate;
    final expected =
        rows.length * (settings.amountFor(cpw) ?? perClassRate * cpw);
    final feeDescription = settings.feeTees
        .map((t) => '${t.classes} clase${t.classes == 1 ? "" : "s"} '
            '\$${t.amount.toStringAsFixed(2)}')
        .join(' · ');

    final message = ReminderMessageBuilder.build(
      rows: rows,
      totalCollected: totalCollected,
      expected: expected,
      paidCount: paidCount,
      totalCount: rows.length,
      weekStart: selectedWeek,
      weekEnd: weekEnd,
      feeDescription: feeDescription,
    );

    if (!context.mounted) return;
    final action = await showModalBottomSheet<_ReminderAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => _ReminderSheetBody(
        message: message,
        paidCount: paidCount,
        totalCount: rows.length,
        totalCollected: totalCollected,
        expected: expected,
      ),
    );
    if (action == null) return;

    if (action == _ReminderAction.copy) {
      await Clipboard.setData(ClipboardData(text: message));
      onResult?.call(message);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Resumen copiado al portapapeles'),
            backgroundColor: AppTheme.brandSecondary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // _ReminderAction.whatsapp
    final encoded = Uri.encodeComponent(message);
    final waUri = Uri.parse('https://wa.me/?text=$encoded');
    final ok = await launchUrl(waUri, mode: LaunchMode.externalApplication);
    if (ok) {
      onResult?.call(message);
      return;
    }
    // Fallback: si no se pudo abrir WhatsApp, copia al clipboard.
    await Clipboard.setData(ClipboardData(text: message));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo abrir WhatsApp. Resumen copiado al portapapeles.',
          ),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

enum _ReminderAction { copy, whatsapp }

class _ReminderSheetBody extends StatelessWidget {
  final String message;
  final int paidCount;
  final int totalCount;
  final double totalCollected;
  final double expected;

  const _ReminderSheetBody({
    required this.message,
    required this.paidCount,
    required this.totalCount,
    required this.totalCollected,
    required this.expected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(
      locale: 'en_US',
      symbol: r'\$',
      decimalDigits: 2,
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTheme.rMd),
                  ),
                  child: const Icon(
                    Icons.notifications_active_rounded,
                    color: Color(0xFF25D366),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Recordatorio semanal',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Recaudado ${fmt.format(totalCollected)} de ${fmt.format(expected)} · $paidCount/$totalCount pagaron',
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
            const SizedBox(height: 16),
            Container(
              constraints: const BoxConstraints(maxHeight: 280),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppTheme.rMd),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Scrollbar(
                child: SingleChildScrollView(
                  child: SelectableText(
                    message,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.chat_rounded),
              label: const Text('Enviar por WhatsApp'),
              onPressed: () =>
                  Navigator.pop(context, _ReminderAction.whatsapp),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copiar al portapapeles'),
              onPressed: () => Navigator.pop(context, _ReminderAction.copy),
            ),
          ],
        ),
      ),
    );
  }
}
