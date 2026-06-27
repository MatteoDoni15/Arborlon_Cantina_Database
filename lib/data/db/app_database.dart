import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Apertura e schema del database locale SQLite.
///
/// Tutto vive sul telefono: l'app funziona al 100% senza internet.
/// Lo schema e' pensato per la sincronizzazione futura (campi updated_at /
/// deleted su ogni tabella).
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'cantina_vini.db');
    return openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE wines (
        id          TEXT PRIMARY KEY,
        name        TEXT NOT NULL,
        producer    TEXT NOT NULL DEFAULT '',
        vintage     INTEGER,
        type        TEXT NOT NULL DEFAULT '',
        region      TEXT NOT NULL DEFAULT '',
        supplier    TEXT NOT NULL DEFAULT '',
        location    TEXT NOT NULL DEFAULT '',
        price_buy   REAL NOT NULL DEFAULT 0,
        price_sell  REAL NOT NULL DEFAULT 0,
        notes       TEXT NOT NULL DEFAULT '',
        photo_path  TEXT,
        updated_at  INTEGER NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE movements (
        id          TEXT PRIMARY KEY,
        wine_id     TEXT NOT NULL,
        kind        TEXT NOT NULL,
        quantity    INTEGER NOT NULL,
        unit_price  REAL NOT NULL DEFAULT 0,
        note        TEXT NOT NULL DEFAULT '',
        photo_path  TEXT,
        device_id   TEXT NOT NULL DEFAULT '',
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_movements_wine ON movements(wine_id)');

    // Tabella chiave-valore per impostazioni (device id, ultima sync, ecc.)
    await db.execute('''
      CREATE TABLE app_meta (
        key   TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  Future<String?> getMeta(String key) async {
    final db = await database;
    final rows =
        await db.query('app_meta', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setMeta(String key, String value) async {
    final db = await database;
    await db.insert('app_meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
