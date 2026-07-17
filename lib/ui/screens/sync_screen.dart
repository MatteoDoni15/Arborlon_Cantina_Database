import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/trusted_peers.dart';
import '../../sync/auto_sync_service.dart';
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
  bool _autoEnabled = true;

  @override
  void initState() {
    super.initState();
    _autoEnabled = AutoSyncService.instance.enabled;
    TrustedPeers.instance.load();
  }

  @override
  void dispose() {
    // Con l'auto-sync attivo il server deve restare acceso anche fuori da
    // questa schermata: e' cio' che ci rende trovabili dai colleghi.
    if (!AutoSyncService.instance.enabled) _sync.stopHost();
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

          const SizedBox(height: 24),
          _autoSyncSection(),
          const SizedBox(height: 16),
          _hotspotCard(),
        ],
      ),
    );
  }

  Widget _autoSyncSection() {
    final auto = AutoSyncService.instance;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Sincronizzazione automatica'),
            subtitle: Text(
                'Con l\'app aperta, ogni ${AutoSyncService.checkEvery.inMinutes} '
                'minuti cerco i telefoni fidati sulla rete e mi allineo da solo '
                '(anche l\'altro telefono deve avere l\'app aperta).'),
            value: _autoEnabled,
            onChanged: (v) async {
              await auto.setEnabled(v);
              // Se stavamo mostrando il QR, il server deve restare su.
              if (!v && _host != null) await _sync.startHost();
              setState(() => _autoEnabled = v);
            },
          ),
          if (_autoEnabled)
            ValueListenableBuilder<String?>(
              valueListenable: auto.lastOutcome,
              builder: (context, outcome, _) => outcome == null
                  ? const SizedBox.shrink()
                  : ListTile(
                      dense: true,
                      leading: const Icon(Icons.autorenew, size: 20),
                      title: Text(outcome,
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
            ),
          AnimatedBuilder(
            animation: TrustedPeers.instance,
            builder: (context, _) {
              final peers = TrustedPeers.instance.all;
              if (peers.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    'Nessun dispositivo fidato. Fai una prima sincronizzazione '
                    'col QR: da quel momento vi riconoscerete da soli.',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                );
              }
              final fmt = DateFormat('dd/MM HH:mm', 'it_IT');
              return Column(
                children: [
                  for (final p in peers)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.smartphone),
                      title: Text(p.name),
                      subtitle: Text(p.lastSync == null
                          ? 'Mai sincronizzato'
                          : 'Ultima sync: ${fmt.format(p.lastSync!)}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Rimuovi dai fidati',
                        onPressed: () => _removePeer(p),
                      ),
                    ),
                  if (_autoEnabled)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8, bottom: 4),
                        child: TextButton.icon(
                          onPressed: () => AutoSyncService.instance.checkNow(),
                          icon: const Icon(Icons.search),
                          label: const Text('Cerca ora'),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _hotspotCard() {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.wifi_tethering),
        title: const Text('Nessun WiFi? Usa l\'hotspot'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: const [
          Text(
            'Anche senza la rete del ristorante potete sincronizzarvi:\n\n'
            '1. Su UN telefono attiva l\'hotspot personale '
            '(Impostazioni → Hotspot).\n'
            '2. Collega l\'altro telefono a quell\'hotspot, come a una '
            'normale rete WiFi.\n'
            '3. Torna qui e usa il QR come al solito. Funziona anche tra '
            'Android e iPhone, e vale pure per la sincronizzazione '
            'automatica.',
          ),
        ],
      ),
    );
  }

  Future<void> _removePeer(TrustedPeer peer) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rimuovere ${peer.name}?'),
        content: const Text(
            'Non verra\' piu\' cercato dalla sincronizzazione automatica. '
            'Potrai riaggiungerlo con una sync via QR.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Rimuovi')),
        ],
      ),
    );
    if (ok == true) await TrustedPeers.instance.remove(peer.deviceId);
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
        _snack('Rete non rilevata. Connettiti al WiFi del ristorante '
            'oppure attiva un hotspot (vedi in basso).');
        if (!AutoSyncService.instance.enabled) await _sync.stopHost();
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
