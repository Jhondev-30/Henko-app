import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_config.dart';
import '../models/member.dart';
import '../providers/home_providers.dart';
import '../providers/payments_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/header_stats.dart';
import '../widgets/member_tile.dart';
import '../widgets/pay_sheet.dart';
import '../widgets/shimmer.dart';
import 'add_member_screen.dart';
import 'member_detail_screen.dart';
import 'week_history_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _picker = ImagePicker();
  bool _searchActive = false;
  String _searchQuery = '';

  // ── Pickers ────────────────────────────────────────────────────────

  Future<String?> _pickImage(BuildContext context) async {
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
      _snack('No se pudo abrir la imagen: $e', isError: true);
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
        debugPrint('Henko: readBytes error → $e');
        return null;
      }
    }
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'screenshots'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final dest = p.join(
        dir.path,
        'pay_${DateTime.now().millisecondsSinceEpoch}'
            '${p.extension(picked.path)}',
      );
      await File(picked.path).copy(dest);
      return dest;
    } catch (e) {
      debugPrint('Henko: copy error → $e');
      return picked.path;
    }
  }

  // ── Acciones de pago ─────────────────────────────────────────────

  Future<void> _onTapPayButton(Member member) async {
    final memberId = member.id;
    if (memberId == null) return;
    final memberName = member.name;

    // ¿Ya está pagado? → confirmar desmarcar (advierte sobre capture).
    final status = ref.read(currentWeekStatusProvider).value;
    final existing = status?[memberId];
    if (existing != null) {
      if (!mounted) return;
      final hasCap = (existing.screenshotPath != null &&
          existing.screenshotPath!.isNotEmpty);
      final confirm = await PayActionSheet.showForUnmarking(
        context,
        memberName: memberName,
        hasCapture: hasCap,
      );
      if (!confirm) return;
      if (!mounted) return;
      try {
        await ref
            .read(paymentsNotifierProvider.notifier)
            .unmarkPaid(memberId);
        if (mounted) _snack('Pago desmarcado');
      } catch (e) {
        if (mounted) _snack('Error: $e', isError: true);
      }
      return;
    }

    // NO está pagado → mostrar sheet con opciones.
    if (!mounted) return;
    final action = await PayActionSheet.showForMarking(context, member);
    if (action == PayAction.cancel) return;
    if (!mounted) return;

    String? screenshotPath;
    if (action == PayAction.withCapture) {
      screenshotPath = await _pickImage(context);
      if (screenshotPath == null) return;
    }
    if (!mounted) return;
    try {
      await ref.read(paymentsNotifierProvider.notifier).markPaid(
            memberId: memberId,
            amount: AppConfig.weeklyFee,
            screenshotPath: screenshotPath,
          );
      if (mounted) {
        _snack(screenshotPath != null
            ? '✓ Pagado con captura'
            : '✓ Pagado');
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

  void _openAddMember() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddMemberScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersWithStatusProvider);
    final scheme = Theme.of(context).colorScheme;

    final filteredItems = _searchQuery.trim().isEmpty
        ? membersAsync.valueOrNull ?? []
        : (membersAsync.valueOrNull ?? [])
            .where((m) => m.member.name
                .toLowerCase()
                .contains(_searchQuery.trim().toLowerCase()))
            .toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(membersWithStatusProvider);
          ref.invalidate(currentWeekStatsProvider);
          await ref.read(membersWithStatusProvider.future);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 280,
              backgroundColor: scheme.primary,
              foregroundColor: Colors.white,
              // Title "Henko" solo cuando colapsa.
              title: LayoutBuilder(
                builder: (ctx, c) {
                  final h = c.biggest.height;
                  final showTitle = h <= kToolbarHeight + 12;
                  return AnimatedOpacity(
                    opacity: showTitle ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Text(AppConfig.appName),
                  );
                },
              ),
              centerTitle: true,
              // Logo como leading (siempre visible).
              leading: Padding(
                padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.rSm),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.rSm),
                    child: Image.asset(
                      'assets/henko_logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              leadingWidth: 56,
              flexibleSpace: const FlexibleSpaceBar(
                background: HeaderStats(),
                collapseMode: CollapseMode.pin,
              ),
              actions: [
                IconButton(
                  tooltip: _searchActive ? 'Cerrar búsqueda' : 'Buscar',
                  icon: Icon(_searchActive
                      ? Icons.close_rounded
                      : Icons.search_rounded),
                  onPressed: () {
                    setState(() {
                      _searchActive = !_searchActive;
                      if (!_searchActive) _searchQuery = '';
                    });
                  },
                ),
                IconButton(
                  tooltip: 'Historial',
                  icon: const Icon(Icons.history_rounded),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const WeekHistoryScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            // Búsqueda como sliver (animada).
            SliverAnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _searchActive ? 1 : 0,
              sliver: SliverToBoxAdapter(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  child: _searchActive
                      ? _SearchBar(
                          onChanged: (v) => setState(() => _searchQuery = v),
                          onClear: () => setState(() => _searchQuery = ''),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
            // Contenido
            membersAsync.when(
              data: (_) {
                if (filteredItems.isEmpty) {
                  if (_searchQuery.trim().isNotEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: _NoSearchResults(query: _searchQuery.trim()),
                    );
                  }
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(onAdd: _openAddMember),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.only(top: 4, bottom: 100),
                  sliver: SliverList.separated(
                    itemCount: filteredItems.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, i) {
                      final item = filteredItems[i];
                      return MemberTile(
                        member: item.member,
                        payment: item.payment,
                        onTapPayButton: () => _onTapPayButton(item.member),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MemberDetailScreen(
                                member: item.member,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                );
              },
              loading: () => SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => const ShimmerMemberTile(),
                  childCount: 6,
                ),
              ),
              error: (e, _) => SliverFillRemaining(
                child: Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddMember,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Agregar'),
      ),
    );
  }
}

class _SearchBar extends StatefulWidget {
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  const _SearchBar({required this.onChanged, required this.onClear});

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          hintText: 'Buscar miembro por nombre...',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (_, v, __) => v.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _controller.clear();
                      widget.onClear();
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  final String query;
  const _NoSearchResults({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Sin resultados para "$query"',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppTheme.brandPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.groups_2_rounded,
                  size: 48, color: AppTheme.brandPrimary),
            ),
            const SizedBox(height: 20),
            const Text(
              'Aún no hay miembros',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Agregá a las personas del henko para empezar a registrar pagos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Agregar primer miembro'),
            ),
          ],
        ),
      ),
    );
  }
}
