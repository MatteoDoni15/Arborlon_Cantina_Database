import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../data/db/app_database.dart';
import '../services/device_service.dart';
import '../services/trusted_peers.dart';
import 'p2p_sync_service.dart';

/// Sincronizzazione P2P automatica: finché l'app è aperta, ogni tot minuti
/// cerca i telefoni fidati sulla rete e si allinea da sola.
///
/// Regole:
/// - il server HTTP resta acceso, così SIAMO trovabili dai colleghi;
/// - si sincronizza SOLO con dispositivi già associati via QR (fidati);
/// - prima prova l'ultimo IP noto di ogni fidato; se non risponde,
///   scansiona la sottorete (254 indirizzi, `/ping` con timeout breve);
/// - funziona su qualsiasi rete locale: WiFi del ristorante o hotspot.
///
/// Con l'app in background il timer si ferma (Android congelerebbe comunque
/// tutto): riparte da solo al ritorno in primo piano.
class AutoSyncService with WidgetsBindingObserver {
  AutoSyncService._();
  static final AutoSyncService instance = AutoSyncService._();

  /// Ogni quanto cercare i colleghi sulla rete.
  static const checkEvery = Duration(minutes: 5);

  /// Se un fidato si è sincronizzato da meno di così (es. è stato LUI a
  /// trovarci), lo saltiamo: evita che due telefoni si rincorrano a vicenda.
  static const _freshEnough = Duration(minutes: 3);

  static const _kEnabled = 'auto_sync_enabled';

  final _sync = P2pSyncService.instance;
  final _peers = TrustedPeers.instance;
  final _db = AppDatabase.instance;

  Timer? _timer;
  bool _running = false;
  bool _enabled = true;

  bool get enabled => _enabled;

  /// Esito dell'ultimo controllo, mostrato nella schermata sync.
  final ValueNotifier<String?> lastOutcome = ValueNotifier(null);

  /// Da chiamare una volta all'avvio dell'app.
  Future<void> start() async {
    _enabled = (await _db.getMeta(_kEnabled)) != '0';
    await _peers.load();
    WidgetsBinding.instance.addObserver(this);
    if (_enabled) await _activate();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _db.setMeta(_kEnabled, value ? '1' : '0');
    if (value) {
      await _activate();
    } else {
      _timer?.cancel();
      _timer = null;
      await _sync.stopHost();
    }
  }

  /// Forza un controllo immediato (bottone "Cerca ora" nella UI).
  Future<void> checkNow() => _tick(force: true);

  Future<void> _activate() async {
    try {
      await _sync.startHost();
    } catch (_) {
      // Porta occupata o rete assente: riproveremo al prossimo giro.
    }
    _timer?.cancel();
    _timer = Timer.periodic(checkEvery, (_) => _tick());
    // Primo controllo poco dopo l'avvio, con un ritardo casuale: se due
    // telefoni aprono l'app insieme, non si scansionano in contemporanea.
    Timer(Duration(seconds: 10 + Random().nextInt(20)), _tick);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled) return;
    if (state == AppLifecycleState.resumed) {
      _activate();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _tick({bool force = false}) async {
    if (_running || !_enabled) return;
    _running = true;
    try {
      await _peers.load();
      final peers = _peers.all;
      if (peers.isEmpty) return;

      final myIp = await _sync.localIp();
      if (myIp == '0.0.0.0' || !myIp.contains('.')) {
        _report('Nessuna rete: mi riprovo più tardi');
        return;
      }
      // Assicura che il server sia su (es. dopo un ritorno dal background).
      try {
        await _sync.startHost();
      } catch (_) {}

      final now = DateTime.now();
      final due = force
          ? peers
          : [
              for (final p in peers)
                if (p.lastSync == null ||
                    now.difference(p.lastSync!) > _freshEnough)
                  p
            ];
      if (due.isEmpty) {
        _report('Tutto già allineato');
        return;
      }

      // 1) Prova l'ultimo IP noto di ogni fidato (veloce, zero scansione).
      final found = <String, HostInfo>{}; // deviceId -> host
      final missing = <TrustedPeer>[];
      for (final peer in due) {
        HostInfo? h;
        if (peer.ip.isNotEmpty) {
          h = await _sync.probe(peer.ip);
          // L'IP potrebbe essere stato riassegnato a un altro telefono.
          if (h != null && h.deviceId != peer.deviceId) h = null;
        }
        if (h != null) {
          found[peer.deviceId] = h;
        } else {
          missing.add(peer);
        }
      }

      // 2) Chi manca all'appello: scansione della sottorete.
      if (missing.isNotEmpty) {
        final myId = await DeviceService.instance.deviceId();
        final discovered = await _scanSubnet(myIp, myId);
        for (final peer in missing) {
          final h = discovered[peer.deviceId];
          if (h != null) found[peer.deviceId] = h;
        }
      }

      if (found.isEmpty) {
        _report('Nessun collega in rete');
        return;
      }

      // 3) Sincronizza con chi abbiamo trovato (bidirezionale).
      var ok = 0;
      final names = <String>[];
      for (final h in found.values) {
        try {
          final stats = await _sync.syncWithHost(h);
          ok++;
          names.add(stats.peerName);
        } catch (_) {
          // Peer sparito a metà (schermo spento, rete persa): pazienza.
        }
      }
      _report(ok == 0
          ? 'Collega trovato ma sync non riuscita'
          : 'Sincronizzato con ${names.join(', ')}');
    } finally {
      _running = false;
    }
  }

  /// Interroga in parallelo tutti gli indirizzi della sottorete /24.
  /// Ritorna i telefoni con l'app aperta, indicizzati per deviceId.
  Future<Map<String, HostInfo>> _scanSubnet(String myIp, String myId) async {
    final base = myIp.substring(0, myIp.lastIndexOf('.') + 1);
    final ips = [
      for (var i = 1; i <= 254; i++)
        if ('$base$i' != myIp) '$base$i'
    ];
    final result = <String, HostInfo>{};
    const batch = 32;
    for (var i = 0; i < ips.length; i += batch) {
      final chunk = ips.sublist(i, min(i + batch, ips.length));
      final probes = await Future.wait([
        for (final ip in chunk)
          _sync.probe(ip, timeout: const Duration(milliseconds: 500))
      ]);
      for (final h in probes) {
        if (h != null && h.deviceId.isNotEmpty && h.deviceId != myId) {
          result[h.deviceId] = h;
        }
      }
    }
    return result;
  }

  void _report(String msg) {
    final hhmm = DateFormat.Hm('it_IT').format(DateTime.now());
    lastOutcome.value = '$msg ($hhmm)';
  }
}
