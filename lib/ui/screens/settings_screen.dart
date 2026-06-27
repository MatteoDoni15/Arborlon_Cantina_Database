import 'package:flutter/material.dart';

import '../../services/backup_service.dart';
import '../../services/device_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    DeviceService.instance.deviceName().then((n) {
      if (mounted) _name.text = n;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Nome di questo telefono',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
              'Mostrato ai colleghi durante la sincronizzazione (es. "Sala", "Bar").',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.smartphone)),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  await DeviceService.instance.setDeviceName(_name.text);
                  _snack('Nome salvato');
                },
                child: const Text('Salva'),
              ),
            ],
          ),
          const Divider(height: 40),

          Text('Backup e ripristino',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
              'La tua rete di sicurezza: esporta tutto in un file (dati + foto) '
              'da salvare su WhatsApp/Drive. Reimportalo su un telefono nuovo '
              'per recuperare la cantina.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.upload_file),
            label: const Text('Esporta backup'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style:
                OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.download),
            label: const Text('Importa backup'),
          ),
          const Divider(height: 40),

          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Come funziona',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text(
                      '• I dati sono salvati su QUESTO telefono e funzionano '
                      'senza internet.\n'
                      '• La sincronizzazione avviene sul WiFi del ristorante '
                      'tra i telefoni dei colleghi.\n'
                      '• Fai un backup ogni tanto: è la copia di sicurezza se un '
                      'telefono si rompe.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      await BackupService.instance.exportAndShare();
    } catch (e) {
      _snack('Errore export: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final result = await BackupService.instance.importFromFile();
      if (result == null) {
        _snack('Nessun file selezionato');
      } else {
        _snack(
            'Importati: ${result.winesUpdated} vini, ${result.movementsUpdated} movimenti');
      }
    } catch (e) {
      _snack('Errore import: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}
