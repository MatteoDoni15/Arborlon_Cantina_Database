import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../sync/p2p_sync_service.dart';

/// Sincronizzazione tra telefoni sullo stesso WiFi.
///
/// Un telefono mostra il QR ("Ricevi"), l'altro lo inquadra ("Invia"):
/// la sincronizzazione e' comunque bidirezionale (entrambi si aggiornano).
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _sync = P2pSyncService.instance;
  HostInfo? _host;
  bool _starting = false;

  @override
  void dispose() {
    _sync.stopHost();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sincronizza con un collega')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.wifi),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'I due telefoni devono essere sulla stessa rete WiFi '
                      '(quella del ristorante). Uno mostra il QR, l\'altro lo '
                      'inquadra. I dati si scambiano in entrambe le direzioni.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (_host == null) ...[
            FilledButton.icon(
              onPressed: _starting ? null : _startHosting,
              icon: const Icon(Icons.qr_code_2),
              label: const Text('Mostra il QR (ricevo io)'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              onPressed: _openScanner,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Inquadra un QR (sincronizza ora)'),
            ),
          ] else
            _qrView(_host!),
        ],
      ),
    );
  }

  Widget _qrView(HostInfo host) {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text('Fai inquadrare questo QR all\'altro telefono',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                QrImageView(
                  data: host.toQr(),
                  size: 240,
                  version: QrVersions.auto,
                ),
                const SizedBox(height: 16),
                Text('${host.name}  ·  ${host.ip}:${host.port}',
                    style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                const Text('In attesa del collega...',
                    style: TextStyle(fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () async {
            await _sync.stopHost();
            setState(() => _host = null);
          },
          icon: const Icon(Icons.stop),
          label: const Text('Interrompi'),
        ),
      ],
    );
  }

  Future<void> _startHosting() async {
    setState(() => _starting = true);
    try {
      final host = await _sync.startHost();
      if (host.ip == '0.0.0.0') {
        _snack('WiFi non rilevato. Connettiti alla rete del ristorante.');
        await _sync.stopHost();
        return;
      }
      setState(() => _host = host);
    } catch (e) {
      _snack('Impossibile avviare: $e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _openScanner() async {
    final host = await Navigator.push<HostInfo>(
      context,
      MaterialPageRoute(builder: (_) => const _ScannerScreen()),
    );
    if (host == null || !mounted) return;
    await _runSync(host);
  }

  Future<void> _runSync(HostInfo host) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ProgressDialog(),
    );
    try {
      final stats = await _sync.syncWithHost(host);
      if (!mounted) return;
      Navigator.pop(context); // chiudi progress
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Sincronizzazione completata ✅'),
          content: Text('Con: ${stats.peerName}\n\n${stats.summary}'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Sincronizzazione fallita'),
          content: Text(
              'Controlla che l\'altro telefono mostri il QR e siate sulla '
              'stessa rete WiFi.\n\nDettaglio: $e'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK')),
          ],
        ),
      );
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog();
  @override
  Widget build(BuildContext context) {
    return const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Expanded(child: Text('Sincronizzazione in corso...')),
        ],
      ),
    );
  }
}

/// Scanner del QR. Ritorna l'HostInfo letto.
class _ScannerScreen extends StatefulWidget {
  const _ScannerScreen();
  @override
  State<_ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<_ScannerScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inquadra il QR del collega')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) return;
          for (final barcode in capture.barcodes) {
            final raw = barcode.rawValue;
            if (raw == null) continue;
            final host = HostInfo.tryParseQr(raw);
            if (host != null) {
              _handled = true;
              Navigator.pop(context, host);
              return;
            }
          }
        },
      ),
    );
  }
}
