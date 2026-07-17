import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/db/app_database.dart';

/// Un telefono "fidato": associato una volta col QR, da lì in poi la sync
/// automatica lo cerca sulla rete e si allinea senza chiedere niente.
class TrustedPeer {
  final String deviceId;
  final String name;
  final String ip; // ultimo IP noto (il DHCP può cambiarlo: è solo un hint)
  final DateTime? lastSync;

  const TrustedPeer({
    required this.deviceId,
    required this.name,
    required this.ip,
    this.lastSync,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'name': name,
        'ip': ip,
        'lastSync': lastSync?.millisecondsSinceEpoch,
      };

  static TrustedPeer fromJson(Map<String, dynamic> m) => TrustedPeer(
        deviceId: (m['deviceId'] ?? '') as String,
        name: (m['name'] ?? 'Telefono') as String,
        ip: (m['ip'] ?? '') as String,
        lastSync: m['lastSync'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((m['lastSync'] as num).toInt()),
      );
}

/// Elenco persistente dei dispositivi fidati (tabella `app_meta`).
///
/// Si entra nell'elenco SOLO completando una sync manuale via QR (in entrambe
/// le direzioni: chi inquadra memorizza l'host, l'host memorizza chi lo ha
/// inquadrato). L'auto-sync parla esclusivamente con questi dispositivi.
class TrustedPeers extends ChangeNotifier {
  TrustedPeers._();
  static final TrustedPeers instance = TrustedPeers._();

  static const _kPeers = 'trusted_peers';

  final _db = AppDatabase.instance;
  List<TrustedPeer> _peers = [];
  bool _loaded = false;

  List<TrustedPeer> get all => List.unmodifiable(_peers);

  Future<void> load() async {
    if (_loaded) return;
    final raw = await _db.getMeta(_kPeers);
    if (raw != null && raw.isNotEmpty) {
      try {
        _peers = [
          for (final e in jsonDecode(raw) as List)
            TrustedPeer.fromJson(e as Map<String, dynamic>)
        ];
      } catch (_) {
        _peers = [];
      }
    }
    _loaded = true;
    notifyListeners();
  }

  /// Aggiunge o aggiorna un dispositivo dopo una sync riuscita.
  Future<void> record({
    required String deviceId,
    required String name,
    String? ip,
  }) async {
    if (deviceId.isEmpty) return;
    await load();
    final old = _peers.where((p) => p.deviceId == deviceId).firstOrNull;
    final updated = TrustedPeer(
      deviceId: deviceId,
      name: name.isNotEmpty ? name : (old?.name ?? 'Telefono'),
      ip: (ip != null && ip.isNotEmpty) ? ip : (old?.ip ?? ''),
      lastSync: DateTime.now(),
    );
    _peers = [
      for (final p in _peers)
        if (p.deviceId != deviceId) p,
      updated,
    ];
    await _save();
  }

  Future<void> remove(String deviceId) async {
    await load();
    _peers = [
      for (final p in _peers)
        if (p.deviceId != deviceId) p
    ];
    await _save();
  }

  Future<void> _save() async {
    await _db.setMeta(
        _kPeers, jsonEncode([for (final p in _peers) p.toJson()]));
    notifyListeners();
  }
}
