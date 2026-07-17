import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/wine.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../services/dictionary_service.dart';
import '../../services/ocr_service.dart';
import '../../services/photo_service.dart';

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
  String? _photoPath; // etichetta fronte
  String? _photoPathBack; // etichetta retro
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
    _photoPathBack = w?.photoPathBack;
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _photoSlot(
                label: 'Etichetta fronte',
                path: _photoPath,
                onPick: (p) => setState(() => _photoPath = p),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _photoSlot(
                label: 'Etichetta retro',
                path: _photoPathBack,
                onPick: (p) => setState(() => _photoPathBack = p),
              ),
            ),
          ],
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
            label: Text(_photoPathBack != null
                ? 'Leggi etichette fronte e retro (riempi automaticamente)'
                : 'Leggi etichetta fronte (riempi automaticamente)'),
          ),
        ],
      ],
    );
  }

  /// Un riquadro foto (fronte o retro): mostra l'immagine o un segnaposto, con
  /// la X per rimuoverla. [onPick] riceve il nuovo percorso (o null se rimossa).
  Widget _photoSlot({
    required String label,
    required String? path,
    required ValueChanged<String?> onPick,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: () => _pickPhoto(onPick),
          child: path == null
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
                        const Icon(Icons.add_a_photo, size: 32),
                        const SizedBox(height: 6),
                        Text(label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                )
              : Stack(
                  alignment: Alignment.topRight,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(File(path),
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover),
                    ),
                    IconButton(
                      style:
                          IconButton.styleFrom(backgroundColor: Colors.black54),
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => onPick(null),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }

  Future<void> _pickPhoto(ValueChanged<String?> onPick) async {
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
    if (path != null) onPick(path);
  }

  Future<void> _runOcr() async {
    if (_photoPath == null) return;
    setState(() => _ocrRunning = true);
    try {
      // I vini gia' in cantina e il dizionario dei nomi aiutano l'OCR: se una
      // riga letta somiglia a un nome noto, viene proposto quello (corretto).
      final existing = await _repo.winesWithStock();
      final dictionary = await DictionaryService.instance.entries();
      final guess = await OcrService.instance.guessWine(
        _photoPath!,
        backImagePath: _photoPathBack,
        knownNames: [for (final w in existing) w.wine.name],
        dictionary: dictionary,
      );
      if (!mounted) return;
      if (guess.isEmpty) {
        _snack('Nessun testo riconosciuto sull\'etichetta.');
        return;
      }
      setState(() {
        if (_vintage.text.trim().isEmpty && guess.vintage != null) {
          _vintage.text = '${guess.vintage}';
        }
        if (_producer.text.trim().isEmpty && guess.producer.isNotEmpty) {
          _producer.text = guess.producer;
        }
        if (_region.text.trim().isEmpty && guess.region.isNotEmpty) {
          _region.text = guess.region;
        }
      });
      if (guess.candidates.length > 1) {
        final chosen = await _pickOcrName(guess.candidates);
        if (chosen != null && mounted) {
          _applyCandidate(chosen, existing);
        }
      } else if (guess.candidates.isNotEmpty && _name.text.trim().isEmpty) {
        _applyCandidate(guess.candidates.first, existing);
      }
      _snack('Etichetta letta. Controlla e correggi se serve.');
    } catch (e) {
      _snack('OCR non riuscito: $e');
    } finally {
      if (mounted) setState(() => _ocrRunning = false);
    }
  }

  /// Applica il candidato scelto: nome sempre, e — solo sui campi ancora
  /// vuoti — produttore/regione/tipo presi dalla cantina (se il vino c'è
  /// già) o dal dizionario dei nomi.
  void _applyCandidate(OcrCandidate c, List<WineWithStock> existing) {
    Wine? cellar;
    if (c.fromCellar) {
      for (final w in existing) {
        if (w.wine.name == c.text) {
          cellar = w.wine;
          break;
        }
      }
    }
    setState(() {
      _name.text = c.text;
      final producer =
          (cellar?.producer.isNotEmpty ?? false) ? cellar!.producer : c.producer;
      if (_producer.text.trim().isEmpty && producer.isNotEmpty) {
        _producer.text = producer;
      }
      final region =
          (cellar?.region.isNotEmpty ?? false) ? cellar!.region : c.region;
      if (_region.text.trim().isEmpty && region.isNotEmpty) {
        _region.text = region;
      }
      if (cellar != null &&
          cellar.type.isNotEmpty &&
          _wineTypes.contains(cellar.type)) {
        _type = cellar.type;
      }
    });
  }

  /// Lista dei possibili nomi letti dall'etichetta, dal piu' probabile al
  /// meno. Ritorna il candidato scelto, o null se l'utente chiude senza
  /// scegliere.
  Future<OcrCandidate?> _pickOcrName(List<OcrCandidate> candidates) {
    return showModalBottomSheet<OcrCandidate>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Quale di questi è il nome del vino?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in candidates)
                    ListTile(
                      leading: Icon(c.fromCellar
                          ? Icons.inventory_2
                          : c.fromDictionary
                              ? Icons.menu_book
                              : Icons.wine_bar),
                      title: Text(c.text),
                      subtitle: c.fromCellar
                          ? const Text('Già presente in cantina')
                          : c.fromDictionary
                              ? const Text('Dal dizionario dei vini')
                              : null,
                      trailing: Text('${(c.score * 100).round()}%',
                          style: TextStyle(color: Colors.grey.shade600)),
                      onTap: () => Navigator.pop(context, c),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
      photoPathBack: _photoPathBack,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _repo.upsertWine(wine);
    // Propone il nome al dizionario collaborativo (vedi DictionaryService):
    // scrive in una coda locale, la rete parte in background e non blocca.
    await DictionaryService.instance.recordWine(
        name: wine.name, producer: wine.producer, region: wine.region);
    if (mounted) Navigator.pop(context, wine.id);
  }

  double _parsePrice(String s) =>
      double.tryParse(s.trim().replaceAll(',', '.')) ?? 0;

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}
