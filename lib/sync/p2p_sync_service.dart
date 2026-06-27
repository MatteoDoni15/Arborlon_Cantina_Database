import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../data/repositories/inventory_repository.dart';
import '../services/device_service.dart';
import '../services/photo_service.dart';
import 'sync_payload.dart';

/// Sincronizzazione "peer-to-peer" tra telefoni sullo stesso WiFi.
///
/// Un telefono fa da HOST (avvia un piccolo server HTTP e mostra un QR con
/// il proprio indirizzo). L'altro fa da OSPITE: scansiona il QR e avvia una
/// sincronizzazione bidirezionale (manda i propri dati, riceve quelli
/// dell'host, e si scambiano le foto mancanti). Nessun server esterno,
/// nessun internet: solo la rete locale del ristorante.
class P2pSyncService {
  P2pSyncService._();
  static final P2pSyncService instance = P2pSyncService._();

  static const int port = 8077;

  final _repo = InventoryRepository.instance;
  final _photos = PhotoService.instance;

  HttpServer? _server;
  bool get isHosting => _server != null;

  // ----------------------------------------------------------------- HOST

  /// Avvia il server. Ritorna le info da incapsulare nel QR.
  Future<HostInfo> startHost() async {
    if (_server != null) {
      return HostInfo(
        ip: await _wifiIp(),
        port: port,
        name: await DeviceService.instance.deviceName(),
        deviceId: await DeviceService.instance.deviceId(),
      );
    }

    final router = Router()
      ..get('/ping', _handlePing)
      ..get('/payload', _handleGetPayload)
      ..post('/payload', _handlePostPayload)
      ..get('/photo/<name>', _handleGetPhoto)
      ..post('/photo/<name>', _handlePostPhoto);

    _server = await shelf_io.serve(
      const Pipeline().addHandler(router.call),
      InternetAddress.anyIPv4,
      port,
    );

    return HostInfo(
      ip: await _wifiIp(),
      port: port,
      name: await DeviceService.instance.deviceName(),
      deviceId: await DeviceService.instance.deviceId(),
    );
  }

  Future<void> stopHost() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<Response> _handlePing(Request req) async {
    return Response.ok(
      jsonEncode({
        'name': await DeviceService.instance.deviceName(),
        'deviceId': await DeviceService.instance.deviceId(),
      }),
      headers: _jsonHeaders,
    );
  }

  Future<Response> _handleGetPayload(Request req) async {
    final payload = await SyncPayload.fromRepository(_repo);
    return Response.ok(jsonEncode(payload.toJson()), headers: _jsonHeaders);
  }

  Future<Response> _handlePostPayload(Request req) async {
    final body = await req.readAsString();
    final payload = SyncPayload.fromJson(
        jsonDecode(body) as Map<String, dynamic>);
    final resolved =
        await payload.withResolvedPhotoPaths(_photos.resolvePath);
    final result = await resolved.applyTo(_repo);

    // Comunica all'ospite quali foto non abbiamo: ce le inviera' lui.
    final missing = await _missingPhotos(payload.photoFileNames());

    return Response.ok(
      jsonEncode({
        'winesUpdated': result.winesUpdated,
        'movementsUpdated': result.movementsUpdated,
        'missingPhotos': missing.toList(),
      }),
      headers: _jsonHeaders,
    );
  }

  Future<Response> _handleGetPhoto(Request req, String name) async {
    final dir = await _photos.photosDir();
    final f = File(p.join(dir.path, _safe(name)));
    if (!await f.exists()) return Response.notFound('no');
    return Response.ok(await f.readAsBytes(),
        headers: {'content-type': 'application/octet-stream'});
  }

  Future<Response> _handlePostPhoto(Request req, String name) async {
    final dir = await _photos.photosDir();
    final f = File(p.join(dir.path, _safe(name)));
    if (!await f.exists()) {
      await f.writeAsBytes(await req.read().expand((c) => c).toList());
    }
    return Response.ok('ok');
  }

  // ---------------------------------------------------------------- GUEST

  /// Sincronizzazione bidirezionale verso un host. Ritorna le statistiche.
  Future<SyncStats> syncWithHost(HostInfo host,
      {void Function(String step)? onProgress}) async {
    final base = 'http://${host.ip}:${host.port}';
    final client = http.Client();
    try {
      // 1) Scarica i dati dell'host e fondili in locale.
      onProgress?.call('Ricevo i dati da ${host.name}...');
      final getRes = await client
          .get(Uri.parse('$base/payload'))
          .timeout(const Duration(seconds: 20));
      if (getRes.statusCode != 200) {
        throw Exception('Host non raggiungibile (${getRes.statusCode})');
      }
      final hostPayload = SyncPayload.fromJson(
          jsonDecode(getRes.body) as Map<String, dynamic>);
      final hostResolved =
          await hostPayload.withResolvedPhotoPaths(_photos.resolvePath);
      final inResult = await hostResolved.applyTo(_repo);

      // 2) Scarica le foto dell'host che ci mancano.
      onProgress?.call('Scarico le foto mancanti...');
      var photosIn = 0;
      for (final name in await _missingPhotos(hostPayload.photoFileNames())) {
        final pr = await client.get(Uri.parse('$base/photo/$name'));
        if (pr.statusCode == 200) {
          final dir = await _photos.photosDir();
          await File(p.join(dir.path, name)).writeAsBytes(pr.bodyBytes);
          photosIn++;
        }
      }

      // 3) Manda i nostri dati all'host.
      onProgress?.call('Invio i miei dati...');
      final myPayload = await SyncPayload.fromRepository(_repo);
      final postRes = await client
          .post(Uri.parse('$base/payload'),
              headers: _jsonHeaders, body: jsonEncode(myPayload.toJson()))
          .timeout(const Duration(seconds: 20));
      final postJson =
          jsonDecode(postRes.body) as Map<String, dynamic>;
      final outResult = SyncStatsCounts(
        wines: (postJson['winesUpdated'] as num?)?.toInt() ?? 0,
        movements: (postJson['movementsUpdated'] as num?)?.toInt() ?? 0,
      );

      // 4) Carica all'host le foto che gli mancano.
      onProgress?.call('Invio le foto mancanti...');
      var photosOut = 0;
      final missing = (postJson['missingPhotos'] as List? ?? []).cast<String>();
      final dir = await _photos.photosDir();
      for (final name in missing) {
        final f = File(p.join(dir.path, name));
        if (await f.exists()) {
          final up = await client.post(Uri.parse('$base/photo/$name'),
              body: await f.readAsBytes());
          if (up.statusCode == 200) photosOut++;
        }
      }

      return SyncStats(
        received: SyncStatsCounts(
            wines: inResult.winesUpdated,
            movements: inResult.movementsUpdated),
        sent: outResult,
        photosReceived: photosIn,
        photosSent: photosOut,
        peerName: host.name,
      );
    } finally {
      client.close();
    }
  }

  /// Verifica veloce che l'host risponda.
  Future<bool> ping(HostInfo host) async {
    try {
      final res = await http
          .get(Uri.parse('http://${host.ip}:${host.port}/ping'))
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // --------------------------------------------------------------- helpers

  Future<Set<String>> _missingPhotos(Set<String> names) async {
    final dir = await _photos.photosDir();
    final missing = <String>{};
    for (final n in names) {
      if (!await File(p.join(dir.path, n)).exists()) missing.add(n);
    }
    return missing;
  }

  Future<String> _wifiIp() async {
    final ip = await NetworkInfo().getWifiIP();
    return ip ?? '0.0.0.0';
  }

  String _safe(String name) => p.basename(name);

  static const _jsonHeaders = {'content-type': 'application/json'};
}

/// Info dell'host, codificate nel QR.
class HostInfo {
  final String ip;
  final int port;
  final String name;
  final String deviceId;
  const HostInfo({
    required this.ip,
    required this.port,
    required this.name,
    required this.deviceId,
  });

  String toQr() =>
      jsonEncode({'ip': ip, 'port': port, 'name': name, 'deviceId': deviceId});

  static HostInfo? tryParseQr(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (m['ip'] == null || m['port'] == null) return null;
      return HostInfo(
        ip: m['ip'] as String,
        port: (m['port'] as num).toInt(),
        name: (m['name'] ?? 'Telefono') as String,
        deviceId: (m['deviceId'] ?? '') as String,
      );
    } catch (_) {
      return null;
    }
  }
}

class SyncStatsCounts {
  final int wines;
  final int movements;
  const SyncStatsCounts({required this.wines, required this.movements});
}

class SyncStats {
  final SyncStatsCounts received;
  final SyncStatsCounts sent;
  final int photosReceived;
  final int photosSent;
  final String peerName;
  const SyncStats({
    required this.received,
    required this.sent,
    required this.photosReceived,
    required this.photosSent,
    required this.peerName,
  });

  String get summary =>
      'Ricevuti: ${received.wines} vini, ${received.movements} movimenti, '
      '$photosReceived foto · Inviati: ${sent.wines} vini, '
      '${sent.movements} movimenti, $photosSent foto';
}
