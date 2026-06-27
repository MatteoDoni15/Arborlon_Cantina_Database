import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Scatto e archiviazione delle foto sul telefono.
///
/// Le foto vengono copiate in una cartella dedicata dentro l'app, cosi'
/// restano disponibili anche offline e sono incluse nei backup.
class PhotoService {
  PhotoService._();
  static final PhotoService instance = PhotoService._();

  final _picker = ImagePicker();

  Future<Directory> photosDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final photos = Directory(p.join(dir.path, 'photos'));
    if (!await photos.exists()) {
      await photos.create(recursive: true);
    }
    return photos;
  }

  /// Scatta una foto con la fotocamera e la salva. Ritorna il percorso
  /// locale, oppure null se l'utente annulla.
  Future<String?> takePhoto() => _pick(ImageSource.camera);

  /// Sceglie una foto dalla galleria.
  Future<String?> pickFromGallery() => _pick(ImageSource.gallery);

  Future<String?> _pick(ImageSource source) async {
    final XFile? shot = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (shot == null) return null;
    return _store(File(shot.path));
  }

  Future<String> _store(File src) async {
    final dir = await photosDir();
    final name = '${const Uuid().v4()}${p.extension(src.path)}';
    final dest = File(p.join(dir.path, name));
    await dest.writeAsBytes(await src.readAsBytes());
    return dest.path;
  }

  /// Risolve il nome-file di una foto (come arriva da sync/backup) nel
  /// percorso locale completo.
  Future<String> resolvePath(String fileName) async {
    final dir = await photosDir();
    return p.join(dir.path, fileName);
  }

  Future<bool> exists(String? path) async {
    if (path == null || path.isEmpty) return false;
    return File(path).exists();
  }
}
