import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../providers/members_provider.dart';
import '../theme/app_theme.dart';

class AddMemberScreen extends ConsumerStatefulWidget {
  const AddMemberScreen({super.key});

  @override
  ConsumerState<AddMemberScreen> createState() => _AddMemberScreenState();
}

class _AddMemberScreenState extends ConsumerState<AddMemberScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  String? _photoPath;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
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
    if (source == null) return;
    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 800,
      );
    } catch (e) {
      debugPrint('Henko: pickPhoto → $e');
      return;
    }
    if (picked == null) return;
    if (kIsWeb) {
      try {
        final bytes = await picked.readAsBytes();
        if (bytes.isEmpty) return;
        final mime = picked.mimeType ?? 'image/jpeg';
        setState(() => _photoPath = 'data:$mime;base64,${base64Encode(bytes)}');
      } catch (_) {}
      return;
    }
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'member_photos'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final dest = p.join(
        dir.path,
        'member_${DateTime.now().millisecondsSinceEpoch}'
            '${p.extension(picked.path)}',
      );
      await File(picked.path).copy(dest);
      setState(() => _photoPath = dest);
    } catch (e) {
      debugPrint('Henko: copy photo → $e');
      // picked existe aquí; usamos `!` porque el flujo lo garantiza.
      setState(() => _photoPath = picked!.path);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(membersNotifierProvider.notifier).add(
            _controller.text,
            photoPath: _photoPath,
          );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  ImageProvider? _avatarProvider(String path) {
    if (path.startsWith('data:')) {
      try {
        final b64 = path.split(',').last;
        return MemoryImage(base64Decode(b64));
      } catch (_) {
        return null;
      }
    }
    if (path.startsWith('blob:') || path.startsWith('http')) {
      return NetworkImage(path);
    }
    return FileImage(File(path));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo miembro')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickPhoto,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: scheme.outlineVariant, width: 1),
                        ),
                        child: ClipOval(
                          child: _photoPath == null
                              ? Icon(Icons.person_rounded,
                                  size: 56, color: scheme.onSecondaryContainer)
                              : Image(
                                  image: _avatarProvider(_photoPath!)!,
                                  fit: BoxFit.cover,
                                ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.brandPrimary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.brandPrimary
                                  .withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: Text(_photoPath == null
                      ? 'Agregar foto (opcional)'
                      : 'Cambiar foto'),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  hintText: 'Ej. María Rodríguez',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Ingresá un nombre';
                  }
                  if (v.trim().length < 2) {
                    return 'Nombre demasiado corto';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(
                  _saving ? 'Guardando…' : 'Guardar miembro',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
