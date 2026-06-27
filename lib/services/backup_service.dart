import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/repositories/inventory_repository.dart';
import '../sync/sync_payload.dart';
import 'photo_service.dart';

/// Backup e ripristino su file. La "rete di sicurezza": un file .cantina
/// (uno zip) che contiene tutti i dati + le foto, da salvare su
/// WhatsApp/Drive/email e da reimportare su un telefono nuovo.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  final _repo = InventoryRepository.instance;
  final _photos = PhotoService.instance;

  /// Crea il file di backup e apre il foglio di condivisione del sistema.
  Future<String> exportAndShare() async {
    final payload = await SyncPayload.fromRepository(_repo);

    final archive = Archive();
    final jsonBytes = utf8.encode(payload.toJsonString());
    archive.addFile(ArchiveFile('data.json', jsonBytes.length, jsonBytes));

    // Allega le foto referenziate.
    final dir = await _photos.photosDir();
    for (final name in payload.photoFileNames()) {
      final f = File(p.join(dir.path, name));
      if (await f.exists()) {
        final bytes = await f.readAsBytes();
        archive.addFile(
            ArchiveFile('photos/$name', bytes.length, bytes));
      }
    }

    final zipped = ZipEncoder().encode(archive)!;
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final tmp = await getTemporaryDirectory();
    final out = File(p.join(tmp.path, 'cantina_$stamp.cantina'));
    await out.writeAsBytes(zipped);

    await Share.shareXFiles(
      [XFile(out.path, mimeType: 'application/zip')],
      subject: 'Backup cantina vini',
      text: 'Backup del magazzino vini ($stamp).',
    );
    return out.path;
  }

  /// Lascia scegliere un file di backup e lo reimporta (fondendolo).
  Future<MergeResult?> importFromFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return null;

    final file = picked.files.first;
    final bytes = file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null) return null;

    final archive = ZipDecoder().decodeBytes(bytes);

    // 1) Ripristina le foto.
    final dir = await _photos.photosDir();
    String? jsonStr;
    for (final entry in archive) {
      if (!entry.isFile) continue;
      if (entry.name == 'data.json') {
        jsonStr = utf8.decode(entry.content as List<int>);
      } else if (entry.name.startsWith('photos/')) {
        final name = entry.name.substring('photos/'.length);
        final dest = File(p.join(dir.path, name));
        if (!await dest.exists()) {
          await dest.writeAsBytes(entry.content as List<int>);
        }
      }
    }
    if (jsonStr == null) {
      throw const FormatException('File di backup non valido (manca data.json)');
    }

    // 2) Riallinea i percorsi foto e fonde i dati.
    final payload = SyncPayload.fromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>);
    final fixed =
        await payload.withResolvedPhotoPaths(_photos.resolvePath);
    return fixed.applyTo(_repo);
  }
}
