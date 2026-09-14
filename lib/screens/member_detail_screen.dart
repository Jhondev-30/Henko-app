import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/member.dart';
import '../models/payment.dart';
import '../providers/members_provider.dart';
import '../providers/payments_provider.dart';
import '../providers/repositories_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../utils/week_calculator.dart';
import '../widgets/pay_sheet.dart';

class MemberDetailScreen extends ConsumerStatefulWidget {
  final Member member;
  const MemberDetailScreen({super.key, required this.member});

  @override
  ConsumerState<MemberDetailScreen> createState() =>
      _MemberDetailScreenState();
}

class _MemberDetailScreenState extends ConsumerState<MemberDetailScreen> {
  final _picker = ImagePicker();

  // ── Pickers ────────────────────────────────────────────────────────

  Future<String?> _pickImage() => _pickImpl('screenshots');
  Future<String?> _pickMemberPhoto() => _pickImpl('member_photos');

  Future<String?> _pickImpl(String subdir) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1280,
      );
    } catch (e) {
      debugPrint('Henko: pick error → $e');
      return null;
    }
    if (picked == null) return null;
    if (kIsWeb) {
      try {
        final bytes = await picked.readAsBytes();
        if (bytes.isEmpty) return null;
        final mime = picked.mimeType ?? 'image/jpeg';
        return 'data:$mime;base64,${base64Encode(bytes)}';
      } catch (e) {
        debugPrint('Henko: readBytes → $e');
        return null;
      }
    }
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, subdir));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final prefix = subdir == 'screenshots' ? 'pay' : 'member';
      final idPart = subdir == 'screenshots'
          ? '${DateTime.now().millisecondsSinceEpoch}'
          : '${widget.member.id}_${DateTime.now().millisecondsSinceEpoch}';
      final dest = p.join(
        dir.path,
        '${prefix}_$idPart${p.extension(picked.path)}',
      );
      await File(picked.path).copy(dest);
      return dest;
    } catch (e) {
      debugPrint('Henko: copy → $e');
      return picked.path;
    }
  }

  // ── Acciones ───────────────────────────────────────────────────────

  Future<void> _changeMemberPhoto() async {
    final path = await _pickMemberPhoto();
    if (path == null) return;
    await ref
        .read(memberRepositoryProvider)
        .updatePhoto(widget.member.id!, path);
    if (!mounted) return;
    ref.invalidate(membersProvider);
    _snack('📷 Foto actualizada');
  }

  Future<void> _openScreenshot(String path) async {
    Widget image;
    if (path.startsWith('data:')) {
      try {
        final b64 = path.split(',').last;
        image = Image.memory(base64Decode(b64), fit: BoxFit.contain);
      } catch (_) {
        image = const Icon(Icons.broken_image, size: 80);
      }
    } else if (path.startsWith('blob:') || path.startsWith('http')) {
      image = Image.network(path, fit: BoxFit.contain);
    } else {
      image = Image.file(File(path), fit: BoxFit.contain);
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          child: InteractiveViewer(child: image),
        ),
      ),
    );
  }

  /// Toggle del pago: si no está pagado, abre el sheet de marking;
  /// si está pagado, pide confirmación para desmarcar.
  Future<void> _toggleThisWeek() async {
    final memberId = widget.member.id;
    if (memberId == null) return;

    final status = ref.read(currentWeekStatusProvider).value;
    final existing = status?[memberId];
    if (existing != null) {
      if (!mounted) return;
      final hasCap = (existing.screenshotPath != null &&
          existing.screenshotPath!.isNotEmpty);
      final confirm = await PaySheet.showForUnmarking(
        context,
        memberName: widget.member.name,
        hasCapture: hasCap,
      );
      if (!confirm) return;
      if (!mounted) return;
      try {
        final weekStart = ref.read(selectedWeekStartProvider);
        await ref
            .read(paymentsNotifierProvider.notifier)
            .unmarkPaid(memberId, weekStart);
        if (mounted) _snack('Pago desmarcado');
      } catch (e) {
        if (mounted) _snack('Error: $e', isError: true);
      }
      return;
    }

    if (!mounted) return;
    final weekStart = ref.read(selectedWeekStartProvider);
    final result = await PaySheet.showForMarking(
      context,
      ref,
      member: widget.member,
      pickImage: _pickImage,
      initialWeekStart: weekStart,
    );
    if (result == null) return;
    if (!mounted) return;
    try {
      await ref.read(paymentsNotifierProvider.notifier).markPaid(
            memberId: memberId,
            amount: result.amount,
            weekStart: result.weekStart,
            classesCount: result.classesCount,
            classesAttended: result.classesAttended,
            screenshotPath: result.screenshotPath,
          );
      if (mounted) {
        final cpw = ref
                .read(settingsProvider)
                .valueOrNull
                ?.defaultClassesPerWeek ??
            2;
        final weeks = (result.classesCount / cpw).floor().clamp(1, 999);
        final msg = weeks > 1
            ? '✓ Pagado · cubre $weeks semanas (${result.classesCount} clases)'
            : (result.withCapture
                ? '✓ Pagado con captura'
                : '✓ Pagado');
        _snack(msg);
      }
    } catch (e) {
      if (mounted) _snack('Error: $e', isError: true);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? AppTheme.error : AppTheme.brandSecondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rMd),
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(memberHistoryProvider(widget.member.id!));
    final currentWeekStatus = ref.watch(currentWeekStatusProvider);
    final scheme = Theme.of(context).colorScheme;
    // Usamos membersProvider para obtener el member actualizado (foto
    // cambia, etc.) en vez del `widget.member` que es del constructor.
    final members = ref.watch(membersProvider).valueOrNull ?? [];
    final member = members.firstWhere(
      (m) => m.id == widget.member.id,
      orElse: () => widget.member,
    );
    final hasPhoto = member.photoPath != null &&
        member.photoPath!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(member.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Eliminar',
            onPressed: () => _confirmDelete(),
          ),
        ],
      ),
      body: history.when(
        data: (payments) {
          final currentPayment = currentWeekStatus.when(
            data: (m) => m[member.id],
            loading: () => null,
            error: (_, __) => null,
          );
          final paidThisWeek = currentPayment != null;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Header con foto + nombre
              Center(
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: scheme.outlineVariant, width: 1),
                          ),
                          child: ClipOval(
                            child: hasPhoto
                                ? _avatarImage(member.photoPath!)
                                : Center(
                                    child: Text(
                                      _initials(member.name),
                                      style: TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.w800,
                                        color: scheme.onSecondaryContainer,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _changeMemberPhoto,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.brandPrimary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.brandPrimary
                                      .withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.camera_alt_rounded,
                                color: Colors.white, size: 18),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      member.name,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Estado del pago esta semana
              Card(
                color: paidThisWeek
                    ? AppTheme.success.withValues(alpha: 0.08)
                    : scheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: paidThisWeek
                              ? AppTheme.success.withValues(alpha: 0.15)
                              : scheme.surfaceContainerHigh,
                          borderRadius:
                              BorderRadius.circular(AppTheme.rMd),
                        ),
                        child: Icon(
                          paidThisWeek
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: paidThisWeek
                              ? AppTheme.success
                              : scheme.onSurfaceVariant,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Esta semana',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant)),
                            const SizedBox(height: 2),
                            Text(
                              paidThisWeek ? 'Pagado' : 'Pendiente',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    color: paidThisWeek
                                        ? AppTheme.success
                                        : scheme.onSurface,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: _toggleThisWeek,
                        child: Text(paidThisWeek
                            ? 'Desmarcar'
                            : 'Marcar pagado'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Text('Historial',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  Text('${payments.length} pago${payments.length == 1 ? '' : 's'}',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 8),
              if (payments.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppTheme.rLg),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.history_rounded,
                          size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text('Sin pagos registrados todavía',
                          style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                )
              else
                ...payments.map((pay) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PaymentRow(
                        payment: pay,
                        classesPerWeek: ref
                                .watch(settingsSyncProvider)
                                .defaultClassesPerWeek,
                        onUpdateAttendance: (week, taken) async {
                          await ref
                              .read(paymentsNotifierProvider.notifier)
                              .setAttendance(pay.id!, week, taken);
                        },
                        onMoveClasses: (fromWeek, n) async {
                          await ref
                              .read(paymentsNotifierProvider.notifier)
                              .moveClassesToNextWeek(
                                  pay.id!, fromWeek, n);
                          if (mounted) {
                            _snack(
                                '↪ $n clase${n == 1 ? "" : "s"} movida${n == 1 ? "" : "s"} a la próxima semana');
                          }
                        },
                        onOpenScreenshot: pay.screenshotPath != null
                            ? () => _openScreenshot(pay.screenshotPath!)
                            : null,
                        onReplaceScreenshot: () async {
                          final path = await _pickImage();
                          if (path == null) return;
                          await ref
                              .read(paymentsNotifierProvider.notifier)
                              .updateScreenshot(pay.id!, path);
                          if (mounted) _snack('📷 Captura reemplazada');
                        },
                        onDeleteScreenshot: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              icon: const Icon(
                                Icons.image_not_supported_outlined,
                                color: AppTheme.error,
                                size: 32,
                              ),
                              title: const Text('¿Eliminar captura?'),
                              content: const Text(
                                  'El pago se mantiene, solo se borra la imagen adjunta.'),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancelar')),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.error,
                                  ),
                                  onPressed: () =>
                                      Navigator.pop(context, true),
                                  child: const Text('Eliminar'),
                                ),
                              ],
                            ),
                          );
                          if (ok != true) return;
                          await ref
                              .read(paymentsNotifierProvider.notifier)
                              .updateScreenshot(pay.id!, null);
                          if (mounted) _snack('Captura eliminada');
                        },
                        onDeletePayment: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('¿Eliminar pago?'),
                              content: const Text(
                                  'Esta acción no se puede deshacer.'),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancelar')),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.error,
                                  ),
                                  onPressed: () =>
                                      Navigator.pop(context, true),
                                  child: const Text('Eliminar'),
                                ),
                              ],
                            ),
                          );
                          if (ok != true) return;
                          await ref
                              .read(paymentsNotifierProvider.notifier)
                              .deletePayment(pay.id!);
                        },
                      ),
                    )),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.person_off_rounded,
            color: AppTheme.error, size: 32),
        title: const Text('¿Eliminar miembro?'),
        content: const Text(
            'El miembro se marcará como inactivo. Su historial se conserva.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    await ref
        .read(membersNotifierProvider.notifier)
        .softDelete(widget.member.id!);
    if (!mounted) return;
    if (context.mounted) Navigator.pop(context);
  }

  String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Widget _avatarImage(String path) {
    final image = _buildImage(path);
    return image;
  }

  Widget _buildImage(String path) {
    if (path.startsWith('data:')) {
      try {
        final b64 = path.split(',').last;
        return Image.memory(
          base64Decode(b64),
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
      } catch (_) {
        return const SizedBox.shrink();
      }
    }
    if (path.startsWith('blob:') || path.startsWith('http')) {
      return Image.network(path, fit: BoxFit.cover, gaplessPlayback: true);
    }
    return Image.file(File(path), fit: BoxFit.cover, gaplessPlayback: true);
  }
}

class _PaymentRow extends StatelessWidget {
  final Payment payment;
  final VoidCallback? onOpenScreenshot;
  final VoidCallback onReplaceScreenshot;
  final VoidCallback onDeleteScreenshot;
  final VoidCallback onDeletePayment;
  final int classesPerWeek;
  final void Function(DateTime week, int classesTaken) onUpdateAttendance;
  final void Function(DateTime fromWeek, int classesToMove) onMoveClasses;

  const _PaymentRow({
    required this.payment,
    required this.onOpenScreenshot,
    required this.onReplaceScreenshot,
    required this.onDeleteScreenshot,
    required this.onDeletePayment,
    required this.classesPerWeek,
    required this.onUpdateAttendance,
    required this.onMoveClasses,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy', 'es');
    final scheme = Theme.of(context).colorScheme;
    final hasScreenshot =
        payment.screenshotPath != null && payment.screenshotPath!.isNotEmpty;

    // ExpansionTile = details/summary de HTML
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Quita el divider interno del ExpansionTile
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
          iconColor: scheme.onSurfaceVariant,
          collapsedIconColor: scheme.onSurfaceVariant,
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.rSm),
            ),
            child: Icon(
              hasScreenshot
                  ? Icons.image_rounded
                  : Icons.event_available_rounded,
              size: 20,
              color: AppTheme.success,
            ),
          ),
          title: Text(
            WeekCalculator.label(payment.weekStart, payment.weekEnd),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          subtitle: Text(
            'Pagado el ${fmt.format(payment.paidAt)}',
            style: TextStyle(
                color: scheme.onSurfaceVariant, fontSize: 11.5),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '\$${payment.amount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.success,
                  fontSize: 15,
                ),
              ),
              if (hasScreenshot) ...[
                const SizedBox(width: 4),
                const Icon(Icons.attachment_rounded,
                    size: 16, color: AppTheme.success),
              ],
            ],
          ),
          children: [
            if (hasScreenshot)
              GestureDetector(
                onTap: onOpenScreenshot,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                  child: _screenshotPreview(payment.screenshotPath!),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.center,
                child: Text(
                  'Sin captura para esta semana',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
            const SizedBox(height: 8),
            Material(
              color: Colors.transparent,
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.start,
                children: [
                  if (hasScreenshot) ...[
                    TextButton.icon(
                      onPressed: onOpenScreenshot,
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.onSurface,
                      ),
                      icon: const Icon(Icons.zoom_in_rounded, size: 18),
                      label: const Text('Ampliar'),
                    ),
                    TextButton.icon(
                      onPressed: onReplaceScreenshot,
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.onSurface,
                      ),
                      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                      label: const Text('Reemplazar'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onDeleteScreenshot,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.error,
                        side: const BorderSide(color: AppTheme.error),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Eliminar capture'),
                    ),
                  ] else
                    TextButton.icon(
                      onPressed: onReplaceScreenshot,
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.onSurface,
                      ),
                      icon: const Icon(Icons.attach_file_rounded, size: 18),
                      label: const Text('Subir capture'),
                    ),
                  OutlinedButton.icon(
                    onPressed: onDeletePayment,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.onSurfaceVariant,
                      side: BorderSide(color: scheme.outlineVariant),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                    label: const Text('Eliminar pago'),
                  ),
                ],
              ),
            ),
            // Editor de asistencia (solo si el pago cubre varias semanas)
            if (classesPerWeek > 0 &&
                payment.classesCount > classesPerWeek) ...[
              const SizedBox(height: 12),
              _AttendanceEditor(
                payment: payment,
                classesPerWeek: classesPerWeek,
                onUpdate: onUpdateAttendance,
                onMoveNext: onMoveClasses,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _screenshotPreview(String path) {
    if (path.startsWith('data:')) {
      try {
        final b64 = path.split(',').last;
        final bytes = base64Decode(b64);
        return Image.memory(
          bytes,
          height: 200,
          width: double.infinity,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          // Limitamos el ancho de decodificación para que data URLs
          // grandes no rompan la memoria ni tarden en mostrar.
          cacheWidth: 800,
          errorBuilder: (_, __, ___) => _placeholder(),
        );
      } catch (e) {
        debugPrint('Henko: screenshot preview error → $e');
        return _placeholder();
      }
    }
    if (path.startsWith('blob:') || path.startsWith('http')) {
      return Image.network(
        path,
        height: 200,
        width: double.infinity,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return Image.file(
      File(path),
      height: 200,
      width: double.infinity,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return Container(
      height: 180,
      width: double.infinity,
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: Icon(Icons.broken_image_outlined,
          color: Colors.grey.shade500, size: 40),
    );
  }
}

/// Editor de asistencia: muestra cada semana cubierta por el pago
/// y permite ajustar cuántas clases tomó la persona en cada una.
/// Si tomó menos de las pagadas, queda "crédito" que se acumula y se
/// puede mover a la próxima semana con un botón explícito.
class _AttendanceEditor extends StatelessWidget {
  final Payment payment;
  final int classesPerWeek;
  final void Function(DateTime week, int classesTaken) onUpdate;
  final void Function(DateTime fromWeek, int classesToMove) onMoveNext;

  const _AttendanceEditor({
    required this.payment,
    required this.classesPerWeek,
    required this.onUpdate,
    required this.onMoveNext,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fmt = DateFormat('d MMM', 'es');
    final weeks = payment.coveredWeeks(classesPerWeek);

    int totalTaken = 0;
    for (final w in weeks) {
      totalTaken += payment.classesTakenIn(w);
    }
    final totalPaid = payment.classesCount;
    final diff = totalPaid - totalTaken;
    final hasMissing = diff > 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(
          color: hasMissing
              ? AppTheme.warning.withValues(alpha: 0.4)
              : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header con resumen
          Row(
            children: [
              Icon(Icons.event_available_rounded,
                  size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                'Asistencia por semana',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hasMissing
                      ? AppTheme.warning.withValues(alpha: 0.15)
                      : AppTheme.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.rFull),
                ),
                child: Text(
                  hasMissing
                      ? 'Faltan $diff clase${diff == 1 ? "" : "s"}'
                      : '$totalTaken/$totalPaid clases ✓',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: hasMissing
                        ? AppTheme.warning
                        : AppTheme.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            hasMissing
                ? 'La persona pagó $totalPaid clases pero solo tomó $totalTaken. Las ${diff} que faltan son crédito disponible.'
                : 'Pagó $totalPaid clases y tomó $totalTaken. Todo al día.',
            style: TextStyle(
                fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
          if (hasMissing) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppTheme.rSm),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 14, color: AppTheme.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Tip: cuando faltes a una clase, pulsa el ícono '
                      '↪ junto a la semana para mover el crédito a la '
                      'siguiente. El pago se prorroga automáticamente.',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: AppTheme.warning,
                          height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Filas de cada semana
          ...weeks.asMap().entries.map((entry) {
            final idx = entry.key;
            final week = entry.value;
            final taken = payment.classesTakenIn(week);
            final isLastWeek = idx == weeks.length - 1;
            final canMoveNext =
                !isLastWeek && taken > 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 90,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(AppTheme.rSm),
                    ),
                    child: Text(
                      'Sem ${fmt.format(week)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.remove_rounded, size: 16),
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.surfaceContainerHigh,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(28, 28),
                    ),
                    onPressed: taken > 0
                        ? () => onUpdate(week, taken - 1)
                        : null,
                  ),
                  const SizedBox(width: 4),
                  Container(
                    constraints: const BoxConstraints(minWidth: 24),
                    child: Text(
                      '$taken',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: taken >= classesPerWeek
                            ? AppTheme.success
                            : AppTheme.warning,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.add_rounded, size: 16),
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.surfaceContainerHigh,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(28, 28),
                    ),
                    onPressed: () => onUpdate(week, taken + 1),
                  ),
                  // Botón "mover a próxima semana"
                  if (canMoveNext) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Mover 1 clase a la próxima semana',
                      child: IconButton(
                        icon: const Icon(Icons.fast_forward_rounded,
                            size: 16),
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          backgroundColor:
                              AppTheme.brandPrimary.withValues(alpha: 0.10),
                          foregroundColor: AppTheme.brandPrimary,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(28, 28),
                        ),
                        onPressed: () => onMoveNext(week, 1),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    '/ $classesPerWeek esperadas',
                    style: TextStyle(
                        fontSize: 10, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
