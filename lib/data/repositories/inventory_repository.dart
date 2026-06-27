import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
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

  Future<List<WineWithStock>> winesWithStock({String search = ''}) async {
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
      result.add(WineWithStock(wine, (r['stock'] as num).toInt()));
    }
    return result;
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

  Future<void> upsertWine(Wine wine) async {
    final db = await _db.database;
    await db.insert('wines', wine.copyWith(updatedAt: _now).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  Future<void> softDeleteWine(String id) async {
    final db = await _db.database;
    await db.update(
        'wines', {'deleted': 1, 'updated_at': _now},
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
