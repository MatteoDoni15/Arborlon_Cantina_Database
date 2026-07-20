import 'dart:async';

import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/db/app_database.dart';
import '../sync/cloud_config.dart';
import 'app_settings.dart';
import 'text_normalizer.dart';

/// Una voce del dizionario nomi di vino (producer/region possono essere '').
class WineDictEntry {
  final String name;
  final String producer;
  final String region;
  const WineDictEntry({
    required this.name,
    this.producer = '',
    this.region = '',
  });
}

/// Dizionario dei nomi di vino che aiuta l'OCR a riconoscere le etichette.
///
/// Vive in una tabella SQLite locale, caricata dall'asset
/// assets/wine_names.csv: l'OCR funziona sempre offline. L'asset si aggiorna
/// insieme all'app (alza [_assetVersion] quando cambi il file).
///
/// PARTE COLLABORATIVA (vedi supabase/dizionario-vini.sql): quando si salva
/// un vino il cui nome non e' nel dizionario, il nome viene messo in coda
/// (dictionary_outbox) e proposto al cloud alla prima occasione. Quando lo
/// stesso vino arriva da due ristoranti diversi viene confermato, e a ogni
/// release il gestore lo esporta nell'asset: cosi' il dizionario di TUTTI
/// migliora con l'uso, senza ricordare da chi e' arrivata l'informazione.
class DictionaryService {
  DictionaryService._();
  static final DictionaryService instance = DictionaryService._();

  static const _assetPath = 'assets/wine_names.csv';

  /// Alza di 1 quando cambi assets/wine_names.csv: alla prima apertura
  /// l'app reimporta il file nel dizionario locale.
  /// v2: aggiunti 19.333 vini italiani da X-Wines (licenza CC0).
  /// v3: estesi a tutti i ~100.400 vini mondiali di X-Wines.
  static const _assetVersion = 3;

  final _db = AppDatabase.instance;
  List<WineDictEntry>? _cache;
  bool _flushing = false;

  /// Tutte le voci del dizionario (dall'asset). In memoria dopo la prima
  /// lettura; da passare a OcrService.guessWine.
  Future<List<WineDictEntry>> entries() async {
    if (_cache != null) return _cache!;
    await _ensureAssetImported();
    final db = await _db.database;
    final rows = await db.query('dictionary');
    _cache = [
      for (final r in rows)
        WineDictEntry(
          name: (r['name'] ?? '') as String,
          producer: (r['producer'] ?? '') as String,
          region: (r['region'] ?? '') as String,
        ),
    ];
    return _cache!;
  }

  /// Importa l'asset nel DB locale, solo quando [_assetVersion] cambia.
  Future<void> _ensureAssetImported() async {
    final imported = await _db.getMeta('dict_asset_version');
    if (imported == '$_assetVersion') return;
    final raw = await rootBundle.loadString(_assetPath);
    final db = await _db.database;
    final batch = db.batch();
    batch.delete('dictionary', where: "source = 'asset'");
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      final parts = t.split(';');
      final name = parts[0].trim();
      if (name.isEmpty) continue;
      final producer = parts.length > 1 ? parts[1].trim() : '';
      final region = parts.length > 2 ? parts[2].trim() : '';
      batch.insert(
        'dictionary',
        {
          'name_norm': normalizeWineText(name),
          'producer_norm': normalizeWineText(producer),
          'name': name,
          'producer': producer,
          'region': region,
          'source': 'asset',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    await _db.setMeta('dict_asset_version', '$_assetVersion');
    _cache = null;
  }

  /// Da chiamare quando l'utente salva un vino: se il nome non e' gia' nel
  /// dizionario lo mette in coda e prova subito a proporlo al cloud.
  /// Non blocca mai il salvataggio: la parte di rete avviene in background.
  Future<void> recordWine({
    required String name,
    String producer = '',
    String region = '',
  }) async {
    final nameNorm = normalizeWineText(name);
    if (nameNorm.length < 3) return;
    final prodNorm = normalizeWineText(producer);
    final db = await _db.database;
    final known = await db.query('dictionary',
        where: 'name_norm = ? AND producer_norm = ?',
        whereArgs: [nameNorm, prodNorm],
        limit: 1);
    if (known.isNotEmpty) return;
    await db.insert(
      'dictionary_outbox',
      {
        'name': name.trim(),
        'producer': producer.trim(),
        'region': region.trim(),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    unawaited(tryFlush());
  }

  /// Propone al cloud i nomi in coda. Silenzioso: se manca la rete, il login
  /// o il ristorante, riprova semplicemente alla prossima occasione (nuovo
  /// salvataggio o sync cloud).
  Future<void> tryFlush() async {
    if (_flushing || !CloudConfig.isConfigured) return;
    final sb = Supabase.instance.client;
    if (sb.auth.currentUser == null) return;
    final rid = AppSettings.instance.restaurantId;
    if (rid.isEmpty) return;
    _flushing = true;
    try {
      final db = await _db.database;
      final rows = await db.query('dictionary_outbox',
          orderBy: 'created_at', limit: 25);
      for (final r in rows) {
        try {
          await sb.rpc('suggest_wine_name', params: {
            'p_restaurant': rid,
            'p_name': r['name'],
            'p_producer': r['producer'],
            'p_region': r['region'],
          }).timeout(const Duration(seconds: 10));
        } catch (_) {
          break; // offline o server non raggiungibile: si ritentera'
        }
        await db.delete('dictionary_outbox',
            where: 'name = ? AND producer = ?',
            whereArgs: [r['name'], r['producer']]);
      }
    } finally {
      _flushing = false;
    }
  }
}
