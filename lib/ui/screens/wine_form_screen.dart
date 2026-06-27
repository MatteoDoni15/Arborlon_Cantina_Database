import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/wine.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../services/ocr_service.dart';
import '../../services/photo_service.dart';
import '../widgets/photo_thumb.dart';

const _wineTypes = [
  'Rosso',
  'Bianco',
  'Rosato',
  'Bollicine',
  'Dolce/Passito',
  'Altro',
];

/// Crea un nuovo vino o modifica uno esistente.
class WineFormScreen extends StatefulWidget {
  final Wine? existing;
  const WineFormScreen({super.key, this.existing});

  @override
  State<WineFormScreen> createState() => _WineFormScreenState();
}

class _WineFormScreenState extends State<WineFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repo = InventoryRepository.instance;

  late final TextEditingController _name;
  late final TextEditingController _producer;
  late final TextEditingController _vintage;
  late final TextEditingController _region;
  late final TextEditingController _supplier;
  late final TextEditingController _location;
  late final TextEditingController _priceBuy;
  late final TextEditingController _priceSell;
  late final TextEditingController _notes;

  String _type = 'Rosso';
  String? _photoPath;
  bool _ocrRunning = false;

  @override
  void initState() {
    super.initState();
    final w = widget.existing;
    _name = TextEditingController(text: w?.name ?? '');
    _producer = TextEditingController(text: w?.producer ?? '');
    _vintage =
        TextEditingController(text: w?.vintage != null ? '${w!.vintage}' : '');
    _region = TextEditingController(text: w?.region ?? '');
    _supplier = TextEditingController(text: w?.supplier ?? '');
    _location = TextEditingController(text: w?.location ?? '');
    _priceBuy = TextEditingController(
        text: (w?.priceBuy ?? 0) == 0 ? '' : '${w!.priceBuy}');
    _priceSell = TextEditingController(
        text: (w?.priceSell ?? 0) == 0 ? '' : '${w!.priceSell}');
    _notes = TextEditingController(text: w?.notes ?? '');
    if (w != null && w.type.isNotEmpty && _wineTypes.contains(w.type)) {
      _type = w.type;
    }
    _photoPath = w?.photoPath;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _producer,
      _vintage,
      _region,
      _supplier,
      _location,
      _priceBuy,
      _priceSell,
      _notes
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.existing != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Modifica vino' : 'Nuovo vino')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _photoSection(),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Nome vino *', prefixIcon: Icon(Icons.wine_bar)),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Obbligatorio' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _producer,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Produttore / cantina',
                  prefixIcon: Icon(Icons.factory)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _vintage,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Annata',
                        prefixIcon: Icon(Icons.calendar_today)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _type,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: _wineTypes
                        .map((t) =>
                            DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(() => _type = v ?? 'Rosso'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _region,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Regione / denominazione',
                  prefixIcon: Icon(Icons.place)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _supplier,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Fornitore',
                  prefixIcon: Icon(Icons.local_shipping)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _location,
              decoration: const InputDecoration(
                  labelText: 'Posizione in cantina (es. Scaffale A3)',
                  prefixIcon: Icon(Icons.grid_view)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _priceBuy,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Prezzo acquisto €',
                        prefixIcon: Icon(Icons.shopping_cart)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _priceSell,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Prezzo vendita €',
                        prefixIcon: Icon(Icons.sell)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Note', prefixIcon: Icon(Icons.notes)),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: Text(_isEdit ? 'Salva modifiche' : 'Aggiungi alla cantina'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoSection() {
    return Column(
      children: [
        GestureDetector(
          onTap: _photoMenu,
          child: _photoPath == null
              ? Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_a_photo, size: 40),
                        SizedBox(height: 8),
                        Text('Foto etichetta (tocca per scattare)'),
                      ],
                    ),
                  ),
                )
              : Stack(
                  alignment: Alignment.topRight,
                  children: [
                    PhotoThumb(path: _photoPath, size: 160, radius: 16),
                    IconButton(
                      style: IconButton.styleFrom(
                          backgroundColor: Colors.black54),
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => setState(() => _photoPath = null),
                    ),
                  ],
                ),
        ),
        if (_photoPath != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _ocrRunning ? null : _runOcr,
            icon: _ocrRunning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_fix_high),
            label: const Text('Leggi etichetta (riempi automaticamente)'),
          ),
        ],
      ],
    );
  }

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

  Future<void> _runOcr() async {
    if (_photoPath == null) return;
    setState(() => _ocrRunning = true);
    try {
      final guess = await OcrService.instance.guessWine(_photoPath!);
      if (!mounted) return;
      if (guess.name.isEmpty && guess.vintage == null) {
        _snack('Nessun testo riconosciuto sull\'etichetta.');
        return;
      }
      setState(() {
        if (_name.text.trim().isEmpty && guess.name.isNotEmpty) {
          _name.text = guess.name;
        }
        if (_vintage.text.trim().isEmpty && guess.vintage != null) {
          _vintage.text = '${guess.vintage}';
        }
      });
      _snack('Etichetta letta. Controlla e correggi se serve.');
    } catch (e) {
      _snack('OCR non riuscito: $e');
    } finally {
      if (mounted) setState(() => _ocrRunning = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final base = widget.existing;
    final wine = Wine(
      id: base?.id ?? const Uuid().v4(),
      name: _name.text.trim(),
      producer: _producer.text.trim(),
      vintage: int.tryParse(_vintage.text.trim()),
      type: _type,
      region: _region.text.trim(),
      supplier: _supplier.text.trim(),
      location: _location.text.trim(),
      priceBuy: _parsePrice(_priceBuy.text),
      priceSell: _parsePrice(_priceSell.text),
      notes: _notes.text.trim(),
      photoPath: _photoPath,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _repo.upsertWine(wine);
    if (mounted) Navigator.pop(context, wine.id);
  }

  double _parsePrice(String s) =>
      double.tryParse(s.trim().replaceAll(',', '.')) ?? 0;

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}
