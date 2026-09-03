import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/settings_repository.dart';
import '../models/member.dart';
import '../providers/payments_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../utils/week_calculator.dart';

/// Resultado del bottom sheet de pago. El parent decide si llama a
/// markPaid o no.
class PaySheetResult {
  final double amount;
  final int classesAttended;
  final int weeksCovered;
  final DateTime weekStart;
  final String? screenshotPath;
  final bool withCapture;

  const PaySheetResult({
    required this.amount,
    required this.classesAttended,
    required this.weeksCovered,
    required this.weekStart,
    this.screenshotPath,
    this.withCapture = false,
  });
}

/// Bottom sheet rediseñado. Permite:
/// 1. Elegir la semana del pago (cualquier lunes, pasado o futuro).
/// 2. Elegir cuántas clases se tomaron.
/// 3. Ver el monto auto-calculado o escribir un monto personalizado.
/// 4. Adjuntar una captura (opcional).
class PaySheet {
  /// Muestra el sheet para registrar un pago de un miembro.
  /// Retorna `null` si el usuario descarta el sheet (tap afuera / back).
  /// Retorna un [PaySheetResult] si el usuario confirma.
  static Future<PaySheetResult?> showForMarking(
    BuildContext context,
    WidgetRef ref, {
    required Member member,
    required Future<String?> Function() pickImage,
    DateTime? initialWeekStart,
  }) async {
    final settings = ref.read(settingsSyncProvider);
    final initialWeek = initialWeekStart ??
        ref.read(selectedWeekStartProvider);
    final week = initialWeek ?? DateTime.now();
    return showModalBottomSheet<PaySheetResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => _PaySheetBody(
        member: member,
        settings: settings,
        initialWeekStart: week,
        pickImage: pickImage,
      ),
    );
  }

  /// Diálogo de confirmación para desmarcar un pago.
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                  border:
                      Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
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
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Sí, desmarcar'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _PaySheetBody extends ConsumerStatefulWidget {
  final Member member;
  final AppSettings settings;
  final DateTime initialWeekStart;
  final Future<String?> Function() pickImage;

  const _PaySheetBody({
    required this.member,
    required this.settings,
    required this.initialWeekStart,
    required this.pickImage,
  });

  @override
  ConsumerState<_PaySheetBody> createState() => _PaySheetBodyState();
}

class _PaySheetBodyState extends ConsumerState<_PaySheetBody> {
  late DateTime _weekStart;
  int? _selectedClasses; // null = monto personalizado
  late TextEditingController _amountController;
  late TextEditingController _customClassesController;
  String? _screenshotPath;
  bool _pickingImage = false;

  @override
  void initState() {
    super.initState();
    _weekStart = widget.initialWeekStart;
    // Default: la primera tarifa configurada (usualmente 2 clases)
    _selectedClasses =
        widget.settings.feeTees.isNotEmpty ? widget.settings.feeTees.first.classes : 2;
    _amountController = TextEditingController(
      text: _calculateDefaultAmount(_selectedClasses!).toStringAsFixed(2),
    );
    _customClassesController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _customClassesController.dispose();
    super.dispose();
  }

  double _calculateDefaultAmount(int classes) {
    final tier = widget.settings.amountFor(classes);
    if (tier != null) return tier;
    // Si no hay tarifa, usar un fallback razonable
    if (classes == 1) return 1.5;
    if (classes == 2) return 2.5;
    if (classes == 3) return 4.0;
    return 1.5 * classes;
  }

  /// Calcula cuántas semanas cubre el monto actual según la tarifa
  /// seleccionada. Si no hay match exacto, usa la tarifa de 1 clase.
  int _calculateWeeksCovered(double amount, int? classes) {
    if (classes == null) {
      // Monto personalizado: dividir por la tarifa más baja
      // disponible (asumimos 1 clase como referencia).
      final tier = widget.settings.feeTees.isNotEmpty
          ? widget.settings.feeTees.first
          : const FeeTier(classes: 2, amount: 2.5);
      if (tier.amount <= 0) return 1;
      return (amount / tier.amount).floor().clamp(1, 999);
    }
    final tier = widget.settings.amountFor(classes);
    if (tier == null || tier <= 0) return 1;
    return (amount / tier).floor().clamp(1, 999);
  }

  Future<void> _pickWeek() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _weekStart,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2035, 12, 31),
      helpText: 'Elegir semana del pago',
      cancelText: 'Cancelar',
      confirmText: 'Elegir',
    );
    if (picked != null) {
      setState(() {
        _weekStart = WeekCalculator.weekStart(picked);
      });
    }
  }

  Future<void> _pickImageAction() async {
    setState(() => _pickingImage = true);
    try {
      final path = await widget.pickImage();
      if (path != null) {
        setState(() => _screenshotPath = path);
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  void _onSelectClass(int? classes) {
    setState(() {
      _selectedClasses = classes;
      if (classes != null) {
        _amountController.text = _calculateDefaultAmount(classes).toStringAsFixed(2);
      }
    });
  }

  double _parseAmount() {
    final text = _amountController.text.trim();
    if (text.isEmpty) return 0;
    return double.tryParse(text.replaceAll(',', '.')) ?? 0;
  }

  void _onConfirm() {
    final amount = _parseAmount();
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresá un monto válido')),
      );
      return;
    }
    final weeksCovered = _calculateWeeksCovered(amount, _selectedClasses);
    Navigator.of(context).pop(PaySheetResult(
      amount: amount,
      classesAttended: _selectedClasses ?? 2,
      weeksCovered: weeksCovered,
      weekStart: _weekStart,
      screenshotPath: _screenshotPath,
      withCapture: _screenshotPath != null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(
      locale: 'en_US',
      symbol: r'$',
      decimalDigits: 2,
    );
    final amount = _parseAmount();
    final weeks = amount > 0
        ? _calculateWeeksCovered(amount, _selectedClasses)
        : 0;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 4,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppTheme.rMd),
                  ),
                  child: Icon(Icons.payments_outlined,
                      color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.member.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Registrar pago',
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

            // Semana
            _SectionLabel(text: 'Semana del pago'),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickWeek,
              borderRadius: BorderRadius.circular(AppTheme.rMd),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_rounded,
                        size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        WeekCalculator.label(
                          _weekStart,
                          WeekCalculator.weekEnd(_weekStart),
                        ),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                    Icon(Icons.edit_calendar_rounded,
                        size: 18, color: scheme.primary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Número de clases (chips)
            _SectionLabel(text: 'Clases tomadas esta semana'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tier in widget.settings.feeTees)
                  ChoiceChip(
                    label: Text(
                      '${tier.classes} ${tier.classes == 1 ? "clase" : "clases"} · ${fmt.format(tier.amount)}',
                    ),
                    selected: _selectedClasses == tier.classes,
                    onSelected: (sel) {
                      if (sel) _onSelectClass(tier.classes);
                    },
                  ),
                ChoiceChip(
                  label: const Text('Personalizado'),
                  selected: _selectedClasses == null,
                  onSelected: (sel) => _onSelectClass(null),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Monto
            _SectionLabel(text: 'Monto pagado'),
            const SizedBox(height: 6),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                prefixText: r'$ ',
                hintText: '0.00',
              ),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (amount > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppTheme.rSm),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_available_rounded,
                        color: AppTheme.success, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        weeks == 1
                            ? 'Cubre 1 semana'
                            : 'Cubre $weeks semanas seguidas',
                        style: const TextStyle(
                          color: AppTheme.success,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Captura
            _SectionLabel(text: 'Captura del pago (opcional)'),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickingImage ? null : _pickImageAction,
              borderRadius: BorderRadius.circular(AppTheme.rMd),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _screenshotPath != null
                        ? AppTheme.success
                        : scheme.outlineVariant,
                    style: _screenshotPath != null
                        ? BorderStyle.solid
                        : BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                ),
                child: Row(
                  children: [
                    Icon(
                      _screenshotPath != null
                          ? Icons.check_circle_rounded
                          : Icons.attach_file_rounded,
                      color: _screenshotPath != null
                          ? AppTheme.success
                          : scheme.onSurfaceVariant,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _screenshotPath != null
                            ? 'Captura adjunta ✓'
                            : (_pickingImage
                                ? 'Abriendo galería...'
                                : 'Adjuntar comprobante'),
                        style: TextStyle(
                          fontSize: 14,
                          color: _screenshotPath != null
                              ? AppTheme.success
                              : scheme.onSurface,
                          fontWeight: _screenshotPath != null
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (_screenshotPath != null)
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () =>
                            setState(() => _screenshotPath = null),
                        tooltip: 'Quitar captura',
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Botón confirmar
            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.check_rounded),
              label: Text(
                amount > 0 && weeks > 0
                    ? 'Registrar $weeks ${weeks == 1 ? "semana" : "semanas"} · ${fmt.format(amount)}'
                    : 'Registrar pago',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
              onPressed: _onConfirm,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: AppTheme.brandSecondary,
      ),
    );
  }
}
