import 'package:flutter/foundation.dart';

import '../data/db/app_database.dart';

/// Modalità di sincronizzazione scelta dall'utente.
///
/// - [p2p]   → gratis, sullo stesso WiFi (Fase 1, sempre disponibile).
/// - [cloud] → premium, sync a distanza via Supabase (Fase 2, plus).
enum SyncMode { p2p, cloud }

/// Preferenze dell'app (modello freemium) salvate nella tabella `app_meta`.
///
/// Il cloud è un PLUS: non sostituisce il P2P. La modalità [SyncMode.cloud]
/// richiede [premium] attivo; in caso contrario si ricade sempre sul P2P.
///
/// Per ora [premium] è un semplice flag locale (sblocco manuale): i pagamenti
/// reali (Play Billing / Stripe) verranno collegati a questo stesso flag.
///
/// Il ristorante cloud è multi-tenant: l'utente CREA un ristorante (ottenendo
/// un [inviteCode] da dare ai colleghi) oppure ENTRA con un codice. Qui teniamo
/// l'[restaurantId] (uuid generato dal server), il nome e il codice invito.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  final _db = AppDatabase.instance;

  static const _kPremium = 'premium';
  static const _kSyncMode = 'sync_mode';
  static const _kRestaurantId = 'restaurant_id';
  static const _kRestaurantName = 'restaurant_name';
  static const _kInviteCode = 'invite_code';
  static const _kPlan = 'restaurant_plan';
  static const _kPullWm = 'cloud_pull_watermark';
  static const _kPushWm = 'cloud_push_watermark';

  bool _premium = false;
  SyncMode _mode = SyncMode.p2p;
  String _restaurantId = '';
  String _restaurantName = '';
  String _inviteCode = '';
  String _restaurantPlan = 'free';
  bool _loaded = false;

  bool get loaded => _loaded;
  bool get premium => _premium;
  SyncMode get mode => _mode;
  String get restaurantId => _restaurantId;
  String get restaurantName => _restaurantName;
  String get inviteCode => _inviteCode;

  /// Piano del ristorante attivo: 'free' (solo P2P) o 'cloud' (cloud sbloccato).
  /// È la fonte di verità lato server (vedi `restaurants.plan` su Supabase).
  String get restaurantPlan => _restaurantPlan;

  /// True se il ristorante attivo ha l'abbonamento cloud.
  bool get restaurantHasCloud => _restaurantPlan == 'cloud';

  /// True se l'utente ha già scelto/creato un ristorante cloud.
  bool get hasRestaurant => _restaurantId.isNotEmpty;

  /// Il cloud è realmente "in uso" solo se premium + modalità cloud.
  bool get cloudActive => _premium && _mode == SyncMode.cloud;

  /// Carica le preferenze dal DB. Da chiamare una volta all'avvio.
  Future<void> load() async {
    _premium = (await _db.getMeta(_kPremium)) == '1';
    _mode = (await _db.getMeta(_kSyncMode)) == 'cloud'
        ? SyncMode.cloud
        : SyncMode.p2p;
    _restaurantId = (await _db.getMeta(_kRestaurantId)) ?? '';
    _restaurantName = (await _db.getMeta(_kRestaurantName)) ?? '';
    _inviteCode = (await _db.getMeta(_kInviteCode)) ?? '';
    _restaurantPlan = (await _db.getMeta(_kPlan)) ?? 'free';
    _loaded = true;
    notifyListeners();
  }

  Future<void> setPremium(bool value) async {
    _premium = value;
    await _db.setMeta(_kPremium, value ? '1' : '0');
    // Senza premium non si può restare in modalità cloud: torna al P2P.
    if (!value && _mode == SyncMode.cloud) {
      _mode = SyncMode.p2p;
      await _db.setMeta(_kSyncMode, 'p2p');
    }
    notifyListeners();
  }

  Future<void> setMode(SyncMode mode) async {
    _mode = mode;
    await _db.setMeta(_kSyncMode, mode == SyncMode.cloud ? 'cloud' : 'p2p');
    notifyListeners();
  }

  /// Imposta il ristorante cloud attivo (dopo crea/entra). Azzera i watermark
  /// così la prima sync col nuovo ristorante scarica tutto da capo.
  Future<void> setRestaurant({
    required String id,
    required String name,
    required String inviteCode,
    String plan = 'free',
  }) async {
    _restaurantId = id;
    _restaurantName = name;
    _inviteCode = inviteCode;
    _restaurantPlan = plan;
    await _db.setMeta(_kRestaurantId, id);
    await _db.setMeta(_kRestaurantName, name);
    await _db.setMeta(_kInviteCode, inviteCode);
    await _db.setMeta(_kPlan, plan);
    await setCloudPullWatermark(0);
    await setCloudPushWatermark(0);
    notifyListeners();
  }

  /// Aggiorna solo il piano del ristorante attivo (es. dopo un refresh dal
  /// server), senza azzerare i watermark.
  Future<void> setRestaurantPlan(String plan) async {
    _restaurantPlan = plan;
    await _db.setMeta(_kPlan, plan);
    notifyListeners();
  }

  /// Esce dal ristorante cloud corrente (solo lato app: non cancella i dati).
  Future<void> clearRestaurant() async {
    _restaurantId = '';
    _restaurantName = '';
    _inviteCode = '';
    _restaurantPlan = 'free';
    await _db.setMeta(_kRestaurantId, '');
    await _db.setMeta(_kRestaurantName, '');
    await _db.setMeta(_kInviteCode, '');
    await _db.setMeta(_kPlan, 'free');
    await setCloudPullWatermark(0);
    await setCloudPushWatermark(0);
    notifyListeners();
  }

  // --- Watermark di sincronizzazione cloud (letti/scritti al volo) ---------
  //
  // Teniamo due "segnalibri" temporali separati per evitare di ri-scaricare o
  // ri-caricare gli stessi record a ogni sync (vedi CloudSyncService).

  Future<int> cloudPullWatermark() async =>
      int.tryParse(await _db.getMeta(_kPullWm) ?? '') ?? 0;

  Future<void> setCloudPullWatermark(int value) =>
      _db.setMeta(_kPullWm, value.toString());

  Future<int> cloudPushWatermark() async =>
      int.tryParse(await _db.getMeta(_kPushWm) ?? '') ?? 0;

  Future<void> setCloudPushWatermark(int value) =>
      _db.setMeta(_kPushWm, value.toString());
}
