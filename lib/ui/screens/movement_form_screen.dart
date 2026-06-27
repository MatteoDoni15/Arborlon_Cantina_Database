import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/movement.dart';
import '../../data/models/wine.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../services/device_service.dart';
import '../../services/photo_service.dart';
import '../widgets/photo_thumb.dart';

/// Registra un CARICO (acquisto) o uno SCARICO (vendita) per un vino.
class MovementFormScreen extends StatefulWidget {
  final Wine wine;
  final MovementKind kind;
  const MovementFormScreen({
    super.key,
    required this.wine,
    required this.kind,
  });

  @override
  State<MovementFormScreen> createState() => _MovementFormScreenState();
}

class _MovementFormScreenState extends State<MovementFormScreen> {
  final _repo = InventoryRepository.instance;
  int _qty = 1;
  late final TextEditingController _price;
  final _note = TextEditingController();
  String? _photoPath;
  bool _saving = false;

  bool get _isIn => widget.kind == MovementKind.inbound;

  @override
  void initState() {
    super.initState();
    final suggested = _isIn ? widget.wine.priceBuy : widget.wine.priceSell;
    _price = TextEditingController(
        text: suggested == 0 ? '' : '$suggested');
  }

  @override
  void dispose() {
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _isIn ? Colors.green.shade700 : Colors.red.shade700;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isIn ? 'Carico (acquisto)' : 'Scarico (vendita)'),
        backgroundColor: color,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.wine.label,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // Quantita'
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('Quante bottiglie?',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _stepBtn(Icons.remove,
                          () => setState(() => _qty = (_qty - 1).clamp(1, 9999))),
                      SizedBox(
                        width: 90,
                        child: Text('$_qty',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                                color: color)),
                      ),
                      _stepBtn(Icons.add,
                          () => setState(() => _qty = (_qty + 1).clamp(1, 9999))),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _price,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText:
                  _isIn ? 'Prezzo unitario acquisto €' : 'Prezzo unitario vendita €',
              prefixIcon: const Icon(Icons.euro),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
                labelText: 'Note (opzionale)', prefixIcon: Icon(Icons.notes)),
          ),
          const SizedBox(height: 16),

          // Foto del movimento
          GestureDetector(
            onTap: _photoMenu,
            child: _photoPath == null
                ? Container(
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add_a_photo, size: 36),
                          const SizedBox(height: 8),
                          Text(_isIn
                              ? 'Foto dell\'acquisto'
                              : 'Foto della vendita'),
                        ],
                      ),
                    ),
                  )
                : Stack(
                    alignment: Alignment.topRight,
                    children: [
                      PhotoThumb(path: _photoPath, size: 140, radius: 16),
                      IconButton(
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.black54),
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => setState(() => _photoPath = null),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 24),

          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Icon(_isIn ? Icons.download : Icons.upload),
            label: Text(_isIn
                ? 'Registra carico (+$_qty)'
                : 'Registra scarico (−$_qty)'),
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) => IconButton.filledTonal(
        iconSize: 28,
        onPressed: onTap,
        icon: Icon(icon),
      );

  Future<void> _photoMenu() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Scatta foto'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Scegli dalla galleria'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
          ],
        ),
      ),
    );
    String? path;
    if (source == 'camera') {
      path = await PhotoService.instance.takePhoto();
    } else if (source == 'gallery') {
      path = await PhotoService.instance.pickFromGallery();
    }
    if (path != null) setState(() => _photoPath = path);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    final deviceId = await DeviceService.instance.deviceId();
    final mov = Movement(
      id: const Uuid().v4(),
      wineId: widget.wine.id,
      kind: widget.kind,
      quantity: _qty,
      unitPrice: double.tryParse(_price.text.trim().replaceAll(',', '.')) ?? 0,
      note: _note.text.trim(),
      photoPath: _photoPath,
      deviceId: deviceId,
      createdAt: now,
      updatedAt: now,
    );
    await _repo.addMovement(mov);
    if (mounted) Navigator.pop(context, true);
  }
}
