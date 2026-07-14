import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repositories/inventory_repository.dart';
import '../services/app_settings.dart';
import '../services/photo_service.dart';
import 'cloud_config.dart';
import 'sync_payload.dart';

/// Sincronizzazione via CLOUD (Fase 2 — premium).
///
/// È un secondo "trasporto" dello stesso [SyncPayload] usato dal P2P: cambia
/// solo il canale (un database Supabase condiviso invece dell'HTTP sul WiFi
/// locale). Il merge è identico — "vince l'ultima modifica" (LWW) — quindi i
/// dati restano coerenti anche mescolando le due modalità.
///
/// NON sostituisce [P2pSyncService]: i due convivono. Un ristorante premium può
/// usare il cloud per la sync a distanza e comunque il P2P quando è in sala.
class CloudSyncService {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();

  final _repo = InventoryRepository.instance;
  final _photos = PhotoService.instance;
  final _settings = AppSettings.instance;

  SupabaseClient get _sb => Supabase.instance.client;

  /// Il cloud è disponibile solo se le chiavi Supabase sono configurate.
  bool get isAvailable => CloudConfig.isConfigured;

  bool get isSignedIn => isAvailable && _sb.auth.currentUser != null;
  String? get currentEmail => isAvailable ? _sb.auth.currentUser?.email : null;

  /// Notifica i cambi di stato dell'autenticazione (per aggiornare la UI).
  Stream<AuthState> get authChanges => _sb.auth.onAuthStateChange;

  // ------------------------------------------------------------------- AUTH

  Future<void> signIn(String email, String password) async {
    _ensureAvailable();
    await _sb.auth.signInWithPassword(email: email.trim(), password: password);
  }

  Future<void> signUp(String email, String password) async {
    _ensureAvailable();
    await _sb.auth.signUp(email: email.trim(), password: password);
  }

  /// Login con Google: apre il browser sulla pagina OAuth di Google e torna
  /// nell'app tramite deep link ([CloudConfig.oauthRedirectUri]). Il metodo
  /// ritorna appena il browser è aperto: l'esito vero arriva in modo asincrono
  /// su [authChanges] quando l'app viene riaperta dal deep link.
  Future<void> signInWithGoogle() async {
    _ensureAvailable();
    await _sb.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: CloudConfig.oauthRedirectUri,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  Future<void> signOut() async {
    if (isAvailable) await _sb.auth.signOut();
  }

  // ------------------------------------------------------------ RISTORANTE

  /// Crea un nuovo ristorante cloud: l'utente corrente ne diventa "owner" e
  /// riceve un codice invito da condividere coi colleghi. Salva il ristorante
  /// come attivo nelle impostazioni.
  Future<RestaurantInfo> createRestaurant(String name) async {
    _ensureSignedIn();
    if (name.trim().isEmpty) throw Exception('Dai un nome al ristorante.');
    final row = await _sb.rpc('create_restaurant', params: {'p_name': name.trim()});
    final info = RestaurantInfo.fromRow(row);
    await _settings.setRestaurant(
        id: info.id,
        name: info.name,
        inviteCode: info.inviteCode,
        plan: info.plan);
    return info;
  }

  /// Entra in un ristorante esistente usando il codice invito. Salva il
  /// ristorante come attivo nelle impostazioni.
  Future<RestaurantInfo> joinRestaurant(String inviteCode) async {
    _ensureSignedIn();
    if (inviteCode.trim().isEmpty) throw Exception('Inserisci il codice invito.');
    final row =
        await _sb.rpc('join_restaurant', params: {'p_code': inviteCode.trim()});
    final info = RestaurantInfo.fromRow(row);
    await _settings.setRestaurant(
        id: info.id,
        name: info.name,
        inviteCode: info.inviteCode,
        plan: info.plan);
    return info;
  }

  /// Rilegge dal server il piano del ristorante attivo e lo salva nelle
  /// impostazioni. Utile per riflettere un abbonamento appena attivato.
  Future<String> refreshPlan() async {
    _ensureSignedIn();
    final rid = _settings.restaurantId;
    if (rid.isEmpty) return _settings.restaurantPlan;
    final row =
        await _sb.from('restaurants').select('plan').eq('id', rid).maybeSingle();
    final plan = (row?['plan'] ?? 'free') as String;
    await _settings.setRestaurantPlan(plan);
    return plan;
  }

  // ------------------------------------------------------- ATTIVAZIONE CLOUD

  /// Invia al gestore la richiesta di attivare il piano cloud per il
  /// ristorante attivo. Ritorna false se c'è già una richiesta in attesa.
  Future<bool> requestCloud() async {
    _ensureSignedIn();
    final rid = _settings.restaurantId;
    if (rid.isEmpty) throw Exception('Crea o entra in un ristorante prima.');
    if (await hasPendingCloudRequest()) return false;
    await _sb.from('cloud_requests').insert({
      'restaurant_id': rid,
      'email': currentEmail ?? '',
    });
    return true;
  }

  /// True se per il ristorante attivo c'è già una richiesta in attesa.
  Future<bool> hasPendingCloudRequest() async {
    _ensureSignedIn();
    final rid = _settings.restaurantId;
    if (rid.isEmpty) return false;
    final row = await _sb
        .from('cloud_requests')
        .select('id')
        .eq('restaurant_id', rid)
        .eq('status', 'pending')
        .maybeSingle();
    return row != null;
  }

  // ------------------------------------------------------------------- SYNC

  /// Sincronizzazione bidirezionale col cloud: prima scarica le novità, poi
  /// invia le proprie. Ritorna le statistiche.
  Future<CloudSyncStats> syncNow({void Function(String step)? onProgress}) async {
    _ensureAvailable();
    if (!isSignedIn) {
      throw Exception('Accedi al cloud prima di sincronizzare.');
    }
    final rid = _settings.restaurantId;
    if (rid.isEmpty) {
      throw Exception('Crea o entra in un ristorante prima di sincronizzare.');
    }

    // 0) Aggiorna il piano del ristorante. Il server rifiuta comunque le
    //    cantine senza piano cloud (RLS): meglio fermarsi qui con un
    //    messaggio chiaro che mostrare un errore criptico del server.
    final plan = await refreshPlan();
    if (plan != 'cloud') {
      throw Exception(
          'Il cloud non è attivo per questo ristorante. Invia la richiesta '
          'di attivazione dalle impostazioni e attendi l\'approvazione.');
    }

    // 1) PULL — scarica i record cambiati dopo l'ultimo pull e fondili.
    onProgress?.call('Scarico le novità dal cloud...');
    final pullWm = await _settings.cloudPullWatermark();
    final remoteWines = await _sb
        .from('wines')
        .select()
        .eq('restaurant_id', rid)
        .gt('updated_at', pullWm);
    final remoteMovements = await _sb
        .from('movements')
        .select()
        .eq('restaurant_id', rid)
        .gt('updated_at', pullWm);

    final pulled = SyncPayload.fromJson({
      'wines': remoteWines,
      'movements': remoteMovements,
    });
    final resolved = await pulled.withResolvedPhotoPaths(_photos.resolvePath);
    final inResult = await resolved.applyTo(_repo);

    onProgress?.call('Scarico le foto mancanti...');
    var photosIn = 0;
    for (final name in await _missingLocalPhotos(pulled.photoFileNames())) {
      if (await _downloadPhoto(rid, name)) photosIn++;
    }

    await _settings.setCloudPullWatermark(_maxUpdatedAt(
      [...pulled.wines, ...pulled.movements].map(_updatedAt),
      pullWm,
    ));

    // 2) PUSH — invia i record modificati localmente dopo l'ultimo push.
    onProgress?.call('Invio i miei dati...');
    final pushWm = await _settings.cloudPushWatermark();
    final localWines = (await _repo.allWinesRaw())
        .where((w) => w.updatedAt > pushWm)
        .toList();
    final localMovements = (await _repo.allMovementsRaw())
        .where((m) => m.updatedAt > pushWm)
        .toList();

    if (localWines.isNotEmpty) {
      await _sb.from('wines').upsert([
        for (final w in localWines) {...w.toSyncJson(), 'restaurant_id': rid},
      ]);
    }
    if (localMovements.isNotEmpty) {
      await _sb.from('movements').upsert([
        for (final m in localMovements)
          {...m.toSyncJson(), 'restaurant_id': rid},
      ]);
    }

    onProgress?.call('Invio le foto...');
    var photosOut = 0;
    final localPayload =
        SyncPayload(wines: localWines, movements: localMovements);
    for (final name in localPayload.photoFileNames()) {
      if (await _uploadPhoto(rid, name)) photosOut++;
    }

    await _settings.setCloudPushWatermark(_maxUpdatedAt(
      [...localWines, ...localMovements].map(_updatedAt),
      pushWm,
    ));

    _repo.notifyChanged();

    return CloudSyncStats(
      received: SyncCounts(
          wines: inResult.winesUpdated, movements: inResult.movementsUpdated),
      sent: SyncCounts(
          wines: localWines.length, movements: localMovements.length),
      photosReceived: photosIn,
      photosSent: photosOut,
    );
  }

  // ---------------------------------------------------------------- helpers

  Future<bool> _uploadPhoto(String rid, String name) async {
    final localPath = await _photos.resolvePath(name);
    final f = File(localPath);
    if (!await f.exists()) return false;
    try {
      await _sb.storage.from(CloudConfig.photosBucket).uploadBinary(
            '$rid/$name',
            await f.readAsBytes(),
            fileOptions: const FileOptions(upsert: true),
          );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _downloadPhoto(String rid, String name) async {
    try {
      final bytes =
          await _sb.storage.from(CloudConfig.photosBucket).download('$rid/$name');
      final dir = await _photos.photosDir();
      await File(p.join(dir.path, name)).writeAsBytes(bytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Set<String>> _missingLocalPhotos(Set<String> names) async {
    final dir = await _photos.photosDir();
    final missing = <String>{};
    for (final n in names) {
      if (!await File(p.join(dir.path, n)).exists()) missing.add(n);
    }
    return missing;
  }

  int _maxUpdatedAt(Iterable<int> values, int fallback) {
    var max = fallback;
    for (final v in values) {
      if (v > max) max = v;
    }
    return max;
  }

  void _ensureAvailable() {
    if (!isAvailable) {
      throw Exception(
          'Cloud non configurato (mancano le chiavi Supabase). Vedi docs/CLOUD-SETUP.md.');
    }
  }

  void _ensureSignedIn() {
    _ensureAvailable();
    if (!isSignedIn) throw Exception('Accedi al cloud prima di continuare.');
  }

  static int _updatedAt(dynamic record) => record.updatedAt as int;
}

/// Dati di un ristorante cloud restituiti dalle funzioni create/join.
class RestaurantInfo {
  final String id; // uuid generato dal server
  final String name;
  final String inviteCode; // codice da dare ai colleghi
  final String plan; // 'free' | 'cloud'
  const RestaurantInfo({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.plan,
  });

  /// Le funzioni SQL restituiscono la riga `restaurants`: PostgREST la manda
  /// come oggetto singolo, ma gestiamo anche il caso di lista (setof).
  factory RestaurantInfo.fromRow(dynamic row) {
    final m = (row is List ? row.first : row) as Map<String, dynamic>;
    return RestaurantInfo(
      id: m['id'] as String,
      name: (m['name'] ?? '') as String,
      inviteCode: (m['invite_code'] ?? '') as String,
      plan: (m['plan'] ?? 'free') as String,
    );
  }
}

class SyncCounts {
  final int wines;
  final int movements;
  const SyncCounts({required this.wines, required this.movements});
}

class CloudSyncStats {
  final SyncCounts received;
  final SyncCounts sent;
  final int photosReceived;
  final int photosSent;
  const CloudSyncStats({
    required this.received,
    required this.sent,
    required this.photosReceived,
    required this.photosSent,
  });

  String get summary =>
      'Ricevuti: ${received.wines} vini, ${received.movements} movimenti, '
      '$photosReceived foto · Inviati: ${sent.wines} vini, '
      '${sent.movements} movimenti, $photosSent foto';
}
