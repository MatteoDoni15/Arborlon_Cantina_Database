import 'dart:convert';

import '../data/models/movement.dart';
import '../data/models/wine.dart';
import '../data/repositories/inventory_repository.dart';

/// Formato dati comune a backup e sincronizzazione P2P.
///
/// Un "payload" e' l'insieme di tutti i vini e movimenti (anche cancellati,
/// perche' la cancellazione va propagata). Le foto viaggiano a parte: qui
/// elenchiamo solo i nomi-file referenziati.
class SyncPayload {
  static const int formatVersion = 1;

  final List<Wine> wines;
  final List<Movement> movements;

  const SyncPayload({required this.wines, required this.movements});

  /// Tutti i nomi-file foto referenziati (per allegarli al backup / scambiarli).
  Set<String> photoFileNames() {
    final names = <String>{};
    for (final w in wines) {
      final n = _basename(w.photoPath);
      if (n != null) names.add(n);
      final b = _basename(w.photoPathBack);
      if (b != null) names.add(b);
    }
    for (final m in movements) {
      final n = _basename(m.photoPath);
      if (n != null) names.add(n);
    }
    return names;
  }

  Map<String, dynamic> toJson() => {
        'format': formatVersion,
        'wines': wines.map((w) => w.toSyncJson()).toList(),
        'movements': movements.map((m) => m.toSyncJson()).toList(),
      };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory SyncPayload.fromJson(Map<String, dynamic> json) {
    final wines = (json['wines'] as List? ?? [])
        .map((e) => Wine.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    final movements = (json['movements'] as List? ?? [])
        .map((e) => Movement.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    return SyncPayload(wines: wines, movements: movements);
  }

  /// Costruisce il payload completo dal database locale.
  static Future<SyncPayload> fromRepository(
      InventoryRepository repo) async {
    final wines = await repo.allWinesRaw();
    final movements = await repo.allMovementsRaw();
    return SyncPayload(wines: wines, movements: movements);
  }

  /// I nomi-file foto contenuti nel payload (basename) vengono tradotti nei
  /// percorsi locali completi tramite [resolve], cosi' che, una volta fusi
  /// nel DB, i record puntino alle foto presenti su QUESTO telefono.
  Future<SyncPayload> withResolvedPhotoPaths(
      Future<String> Function(String fileName) resolve) async {
    final w = <Wine>[];
    for (var wine in wines) {
      if (wine.photoPath != null) {
        wine = wine.copyWith(photoPath: await resolve(wine.photoPath!));
      }
      if (wine.photoPathBack != null) {
        wine = wine.copyWith(photoPathBack: await resolve(wine.photoPathBack!));
      }
      w.add(wine);
    }
    final m = [
      for (final mov in movements)
        mov.photoPath == null
            ? mov
            : mov.copyWith(photoPath: await resolve(mov.photoPath!)),
    ];
    return SyncPayload(wines: w, movements: m);
  }

  /// Fonde questo payload nel database locale (last-write-wins). Ritorna
  /// quanti record sono stati effettivamente aggiornati.
  Future<MergeResult> applyTo(InventoryRepository repo) async {
    var w = 0, m = 0;
    for (final wine in wines) {
      if (await repo.mergeWine(wine)) w++;
    }
    for (final mov in movements) {
      if (await repo.mergeMovement(mov)) m++;
    }
    repo.notifyChanged();
    return MergeResult(winesUpdated: w, movementsUpdated: m);
  }

  static String? _basename(String? p) {
    if (p == null || p.isEmpty) return null;
    return p.replaceAll('\\', '/').split('/').last;
  }
}

class MergeResult {
  final int winesUpdated;
  final int movementsUpdated;
  const MergeResult({
    required this.winesUpdated,
    required this.movementsUpdated,
  });

  int get total => winesUpdated + movementsUpdated;
}
