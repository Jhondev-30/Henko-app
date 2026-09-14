import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../app_config.dart';
import '../data/settings_repository.dart';
import '../providers/members_provider.dart';
import '../providers/payments_provider.dart';
import '../providers/repositories_provider.dart';
import '../providers/settings_provider.dart';
import '../services/backup_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _exporting = false;
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.appName),
        centerTitle: true,
      ),
      body: settingsAsync.when(
        data: (settings) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Sección clases por semana ──
            _SectionTitle(
              icon: Icons.event_repeat_rounded,
              title: 'Clases por semana (default)',
              subtitle:
                  'Cuántas clases se dan normalmente en la semana. Se usa para calcular automáticamente cuántas semanas cubre un pago y el monto esperado.',
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_view_week_rounded,
                        color: AppTheme.brandPrimary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Cantidad de clases por semana',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                          Text(
                            'Cambialo si esta semana o las siguientes tienen más o menos clases (feriado, evento especial, etc.)',
                            style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ClassesPerWeekStepper(
                      value: settings.defaultClassesPerWeek,
                      onChanged: (newValue) {
                        ref.read(settingsRepositoryProvider).save(
                              settings.copyWith(
                                defaultClassesPerWeek: newValue,
                              ),
                            );
                        ref.invalidate(settingsProvider);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Sección tarifas ──
            _SectionTitle(
              icon: Icons.payments_outlined,
              title: 'Tarifas de las clases',
              subtitle:
                  'Cuánto cobra el profesor por N clases en la semana. Cambiá estos valores cuando cambie el precio.',
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < settings.feeTees.length; i++) ...[
                    _FeeTierRow(
                      tier: settings.feeTees[i],
                      onChanged: (newTier) {
                        final newList = List<FeeTier>.from(settings.feeTees);
                        newList[i] = newTier;
                        ref
                            .read(settingsRepositoryProvider)
                            .save(settings.copyWith(feeTiers: newList));
                        ref.invalidate(settingsProvider);
                      },
                      onDelete: settings.feeTees.length > 1
                          ? () {
                              final newList =
                                  List<FeeTier>.from(settings.feeTees);
                              newList.removeAt(i);
                              ref
                                  .read(settingsRepositoryProvider)
                                  .save(settings.copyWith(feeTiers: newList));
                              ref.invalidate(settingsProvider);
                            }
                          : null,
                    ),
                    if (i < settings.feeTees.length - 1)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  ],
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline,
                        color: AppTheme.brandPrimary),
                    title: const Text('Agregar otra tarifa'),
                    subtitle: const Text(
                        'Ej: 4 clases por \$5, 5 clases por \$6, etc.'),
                    onTap: () {
                      // Calcular siguiente número de clases
                      final maxClasses = settings.feeTees
                          .map((t) => t.classes)
                          .reduce((a, b) => a > b ? a : b);
                      final newList = List<FeeTier>.from(settings.feeTees)
                        ..add(FeeTier(
                          classes: maxClasses + 1,
                          amount: 0.0,
                        ));
                      ref
                          .read(settingsRepositoryProvider)
                          .save(settings.copyWith(feeTiers: newList));
                      ref.invalidate(settingsProvider);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppTheme.rMd),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline,
                      size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'El cobro esperado del grupo se calcula con la tarifa más baja (${_formatMoney(settings.feeTees.first.amount)}). Si cada persona toma una cantidad distinta, ajustá desde el perfil del integrante.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Sección backup ──
            _SectionTitle(
              icon: Icons.backup_outlined,
              title: 'Copia de seguridad',
              subtitle:
                  'Exportá todos los miembros, pagos y tarifas a un archivo JSON. Importá uno para restaurar después de reinstalar o en otro dispositivo.',
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.upload_file_rounded,
                        color: AppTheme.brandPrimary),
                    title: const Text('Exportar backup'),
                    subtitle: const Text(
                        'Genera un archivo .json y lo abre para compartirlo'),
                    trailing: _exporting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: _exporting ? null : _onExport,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.download_rounded,
                        color: AppTheme.brandSecondary),
                    title: const Text('Importar backup'),
                    subtitle: const Text(
                        'Reemplaza todos los datos con los del archivo seleccionado'),
                    trailing: _importing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: _importing ? null : _onImport,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppTheme.rMd),
                border: Border.all(
                    color: AppTheme.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppTheme.warning, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Importar REEMPLAZA todos los datos. Hacé un backup antes si querés conservar el estado actual.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Info ──
            _SectionTitle(
              icon: Icons.info_outline,
              title: 'Información',
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  _InfoRow(label: 'Versión de la app', value: '1.3.0'),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _InfoRow(
                      label: 'Base de datos',
                      value: 'SQLite local (privada)'),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _InfoRow(
                      label: 'Tarifa por defecto',
                      value: _formatMoney(
                          settings.feeTees.isNotEmpty
                              ? settings.feeTees.first.amount
                              : 0)),
                ],
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  String _formatMoney(double v) => '\$${v.toStringAsFixed(2)}';

  // ── Export ──

  Future<void> _onExport() async {
    setState(() => _exporting = true);
    try {
      final service = BackupService(
        db: ref.read(databaseProvider),
        memberRepo: ref.read(memberRepositoryProvider),
        paymentRepo: ref.read(paymentRepositoryProvider),
        settingsRepo: ref.read(settingsRepositoryProvider),
      );
      final path = await service.exportToFile();
      if (!mounted) return;
      // Compartir el archivo
      await Share.shareXFiles(
        [XFile(path)],
        text: 'Backup de Henko - Academia de Danza Contemporánea',
        subject: 'henko-backup.json',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Backup exportado: ${path.split(Platform.pathSeparator).last}'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── Import ──

  Future<void> _onImport() async {
    // Confirmar primero
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: AppTheme.warning, size: 32),
        title: const Text('¿Reemplazar datos?'),
        content: const Text(
            'Esto va a BORRAR todos los miembros y pagos actuales y reemplazarlos con los del archivo. ¿Continuar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, reemplazar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _importing = false);
        return;
      }
      final path = result.files.first.path;
      if (path == null) {
        throw 'No se pudo obtener la ruta del archivo';
      }
      final content = await File(path).readAsString();

      final service = BackupService(
        db: ref.read(databaseProvider),
        memberRepo: ref.read(memberRepositoryProvider),
        paymentRepo: ref.read(paymentRepositoryProvider),
        settingsRepo: ref.read(settingsRepositoryProvider),
      );
      await service.importFromJsonString(content);

      // Invalidar todos los providers
      ref.invalidate(settingsProvider);
      ref.invalidate(membersProvider);
      ref.invalidate(currentWeekPaymentsProvider);
      ref.invalidate(currentWeekStatsProvider);
      ref.invalidate(currentWeekStatusProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Backup restaurado correctamente'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al importar: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const _SectionTitle({
    required this.icon,
    required this.title,
    this.subtitle,
  });
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: scheme.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _FeeTierRow extends StatefulWidget {
  final FeeTier tier;
  final ValueChanged<FeeTier> onChanged;
  final VoidCallback? onDelete;
  const _FeeTierRow({
    required this.tier,
    required this.onChanged,
    this.onDelete,
  });
  @override
  State<_FeeTierRow> createState() => _FeeTierRowState();
}

class _FeeTierRowState extends State<_FeeTierRow> {
  late TextEditingController _amountController;
  late TextEditingController _classesController;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    _classesController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _amountController.text = widget.tier.amount.toStringAsFixed(2);
      _classesController.text = widget.tier.classes.toString();
      _initialized = true;
    }
  }

  @override
  void didUpdateWidget(covariant _FeeTierRow old) {
    super.didUpdateWidget(old);
    if (old.tier != widget.tier && !_initialized) {
      _amountController.text = widget.tier.amount.toStringAsFixed(2);
      _classesController.text = widget.tier.classes.toString();
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _classesController.dispose();
    super.dispose();
  }

  void _onSave() {
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.')) ?? 0;
    final classes = int.tryParse(_classesController.text) ?? 1;
    widget.onChanged(FeeTier(classes: classes, amount: amount));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: TextField(
              controller: _classesController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Clases',
                isDense: true,
              ),
              onEditingComplete: _onSave,
            ),
          ),
          const SizedBox(width: 12),
          const Text('=', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                prefixText: r'$ ',
                labelText: 'Monto',
                isDense: true,
              ),
              onEditingComplete: _onSave,
              onSubmitted: (_) => _onSave(),
              onTapOutside: (_) => _onSave(),
            ),
          ),
          if (widget.onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: AppTheme.error, size: 20),
              onPressed: widget.onDelete,
              tooltip: 'Eliminar tarifa',
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label, style: const TextStyle(fontSize: 13)),
      trailing: Text(
        value,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppTheme.brandPrimary,
        ),
      ),
    );
  }
}

class _ClassesPerWeekStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _ClassesPerWeekStepper(
      {required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.brandPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.rFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_rounded),
            onPressed: value > 1 ? () => onChanged(value - 1) : null,
            visualDensity: VisualDensity.compact,
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 32),
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.brandPrimary,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: value < 7 ? () => onChanged(value + 1) : null,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
