import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../models/activity_event.dart';
import '../models/movement.dart';
import '../models/wine.dart';

/// Vino con la sua giacenza attuale (bottiglie) gia' calcolata.
class WineWithStock {
  final Wine wine;
  final int stock;
  const WineWithStock(this.wine, this.stock);
}

/// Punto unico di accesso ai dati. E' un [ChangeNotifier]: le schermate vi si
/// agganciano e si aggiornano da sole quando i dati cambiano.
class InventoryRepository extends ChangeNotifier {
  InventoryRepository._();
  static final InventoryRepository instance = InventoryRepository._();

  final _db = AppDatabase.instance;

  int get _now => DateTime.now().millisecondsSinceEpoch;

  // ----------------------------------------------------------------- WINES

  Future<List<WineWithStock>> winesWithStock({
    String search = '',
    String? type,
    String? grape,
    String? region,
    String? denomination,
    String? country,
  }) async {
    final db = await _db.database;
    // Giacenza = somma con segno dei movimenti non cancellati, per vino.
    final rows = await db.rawQuery('''
      SELECT w.*,
        COALESCE((
          SELECT SUM(CASE WHEN m.kind = 'in' THEN m.quantity ELSE -m.quantity END)
          FROM movements m
          WHERE m.wine_id = w.id AND m.deleted = 0
        ), 0) AS stock
      FROM wines w
      WHERE w.deleted = 0
      ORDER BY w.name COLLATE NOCASE
    ''');

    final q = search.trim().toLowerCase();
    final result = <WineWithStock>[];
    for (final r in rows) {
      final wine = Wine.fromMap(r);
      if (q.isNotEmpty) {
        final hay =
            '${wine.name} ${wine.producer} ${wine.region} ${wine.type} ${wine.supplier}'
                .toLowerCase();
        if (!hay.contains(q)) continue;
      }
      if (type != null && type.isNotEmpty && wine.type != type) continue;
      if (grape != null && grape.isNotEmpty && wine.grape != grape) continue;
      if (region != null && region.isNotEmpty && wine.region != region) {
        continue;
      }
      if (denomination != null &&
          denomination.isNotEmpty &&
          wine.denomination != denomination) {
        continue;
      }
      if (country != null && country.isNotEmpty && wine.country != country) {
        continue;
      }
      result.add(WineWithStock(wine, (r['stock'] as num).toInt()));
    }
    return result;
  }

  /// Valori distinti (non vuoti) presenti tra i vini in cantina per una
  /// delle colonne filtrabili, usati per popolare i menu a tendina dei
  /// filtri. [column] e' ristretta a un elenco noto per sicurezza.
  static const _filterableColumns = {
    'type',
    'grape',
    'region',
    'denomination',
    'country',
  };

  Future<List<String>> distinctWineValues(String column) async {
    if (!_filterableColumns.contains(column)) return [];
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT $column AS v FROM wines
      WHERE deleted = 0 AND TRIM($column) != ''
      ORDER BY $column COLLATE NOCASE
    ''');
    return rows.map((r) => r['v'] as String).toList();
  }

  Future<Wine?> wineById(String id) async {
    final db = await _db.database;
    final rows = await db.query('wines', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Wine.fromMap(rows.first);
  }

  Future<int> stockForWine(String wineId) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN kind = 'in' THEN quantity ELSE -quantity END), 0) AS s
      FROM movements WHERE wine_id = ? AND deleted = 0
    ''', [wineId]);
    return (rows.first['s'] as num).toInt();
  }

  /// Crea o modifica un vino. [authorName] diventa il creatore (se il vino
  /// è nuovo) o l'ultimo modificatore (se già esisteva) per il registro
  /// attività — la data/autore di creazione originali non vengono mai persi.
  Future<void> upsertWine(Wine wine, {required String authorName}) async {
    final db = await _db.database;
    final existing = await wineById(wine.id);
    final now = _now;
    final toSave = wine.copyWith(
      updatedAt: now,
      createdAt: existing?.createdAt ?? now,
      createdBy: existing?.createdBy ?? authorName,
      updatedBy: authorName,
    );
    await db.insert('wines', toSave.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  Future<void> softDeleteWine(String id, {required String authorName}) async {
    final db = await _db.database;
    await db.update(
        'wines',
        {'deleted': 1, 'updated_at': _now, 'updated_by': authorName},
        where: 'id = ?', whereArgs: [id]);
    // Cancella (soft) anche i movimenti collegati.
    await db.update(
        'movements', {'deleted': 1, 'updated_at': _now},
        where: 'wine_id = ?', whereArgs: [id]);
    notifyListeners();
  }

  // ------------------------------------------------------------- MOVEMENTS

  Future<List<Movement>> movementsForWine(String wineId) async {
    final db = await _db.database;
    final rows = await db.query('movements',
        where: 'wine_id = ? AND deleted = 0',
        whereArgs: [wineId],
        orderBy: 'created_at DESC');
    return rows.map(Movement.fromMap).toList();
  }

  Future<List<Movement>> recentMovements({int limit = 50}) async {
    final db = await _db.database;
    final rows = await db.query('movements',
        where: 'deleted = 0', orderBy: 'created_at DESC', limit: limit);
    return rows.map(Movement.fromMap).toList();
  }

  // -------------------------------------------------------- ACTIVITY LOG

  /// Registro attività leggibile: chi ha aggiunto/modificato un vino, chi ha
  /// caricato o venduto bottiglie, in ordine cronologico decrescente.
  /// Ricostruito al volo da vini e movimenti (nessuna tabella dedicata).
  Future<List<ActivityEvent>> recentActivity({int limit = 200}) async {
    final db = await _db.database;
    final events = <ActivityEvent>[];

    final wineRows = await db.query('wines', where: 'deleted = 0');
    for (final r in wineRows) {
      final w = Wine.fromMap(r);
      if (w.createdAt > 0) {
        events.add(ActivityEvent(
          type: ActivityType.wineAdded,
          at: w.createdAt,
          wineId: w.id,
          wineLabel: w.label,
          author: w.createdBy,
        ));
      }
      if (w.updatedBy.isNotEmpty && w.updatedAt > w.createdAt) {
        events.add(ActivityEvent(
          type: ActivityType.wineEdited,
          at: w.updatedAt,
          wineId: w.id,
          wineLabel: w.label,
          author: w.updatedBy,
        ));
      }
    }

    final movRows = await db.rawQuery('''
      SELECT m.*, COALESCE(w.name, '') AS wine_name,
        COALESCE(w.producer, '') AS wine_producer, w.vintage AS wine_vintage
      FROM movements m
      LEFT JOIN wines w ON w.id = m.wine_id
      WHERE m.deleted = 0
      ORDER BY m.created_at DESC
      LIMIT ?
    ''', [limit]);
    for (final r in movRows) {
      final m = Movement.fromMap(r);
      final name = r['wine_name'] as String? ?? '';
      final label = name.isEmpty ? 'Vino eliminato' : _movementWineLabel(r);
      events.add(ActivityEvent(
        type: m.kind == MovementKind.inbound
            ? ActivityType.movementIn
            : ActivityType.movementOut,
        at: m.createdAt,
        wineId: m.wineId,
        wineLabel: label,
        author: m.authorName,
        quantity: m.quantity,
        unitPrice: m.unitPrice,
        note: m.note,
      ));
    }

    events.sort((a, b) => b.at.compareTo(a.at));
    return events.take(limit).toList();
  }

  /// Ricompone l'etichetta del vino (nome, annata, produttore) dalla riga
  /// unita movimento+vino della query di [recentActivity].
  String _movementWineLabel(Map<String, Object?> r) {
    final name = r['wine_name'] as String? ?? '';
    final vintage = r['wine_vintage'] as int?;
    final producer = r['wine_producer'] as String? ?? '';
    final v = vintage != null ? ' $vintage' : '';
    final p = producer.isNotEmpty ? ' · $producer' : '';
    return '$name$v'.trim() + p;
  }

  Future<void> addMovement(Movement m) async {
    final db = await _db.database;
    await db.insert('movements', m.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  Future<void> softDeleteMovement(String id) async {
    final db = await _db.database;
    await db.update('movements', {'deleted': 1, 'updated_at': _now},
        where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  // ------------------------------------------------- SYNC / BACKUP support

  /// Tutti i vini (anche cancellati) per export/sync.
  Future<List<Wine>> allWinesRaw() async {
    final db = await _db.database;
    final rows = await db.query('wines');
    return rows.map(Wine.fromMap).toList();
  }

  Future<List<Movement>> allMovementsRaw() async {
    final db = await _db.database;
    final rows = await db.query('movements');
    return rows.map(Movement.fromMap).toList();
  }

  /// Fonde un vino in arrivo da un altro telefono / da un backup.
  /// Regola: vince la versione con [updatedAt] piu' recente (last-write-wins).
  /// Ritorna true se il record locale e' stato aggiornato.
  Future<bool> mergeWine(Wine incoming) async {
    final db = await _db.database;
    final existing = await wineById(incoming.id);
    if (existing != null && existing.updatedAt >= incoming.updatedAt) {
      return false; // la nostra versione e' uguale o piu' recente
    }
    await db.insert('wines', incoming.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  /// Fonde un movimento in arrivo. I movimenti sono eventi: se non esiste lo
  /// aggiungiamo; se esiste, vince l'updatedAt piu' recente (per correzioni).
  Future<bool> mergeMovement(Movement incoming) async {
    final db = await _db.database;
    final rows = await db
        .query('movements', where: 'id = ?', whereArgs: [incoming.id]);
    if (rows.isNotEmpty) {
      final existing = Movement.fromMap(rows.first);
      if (existing.updatedAt >= incoming.updatedAt) return false;
    }
    await db.insert('movements', incoming.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  void notifyChanged() => notifyListeners();
}
