import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/models/movement.dart';
import '../../data/models/wine.dart';
import '../../data/repositories/inventory_repository.dart';
import '../widgets/formatters.dart';
import '../widgets/photo_thumb.dart';
import 'movement_form_screen.dart';
import 'wine_form_screen.dart';

class WineDetailScreen extends StatefulWidget {
  final String wineId;
  const WineDetailScreen({super.key, required this.wineId});

  @override
  State<WineDetailScreen> createState() => _WineDetailScreenState();
}

class _WineDetailScreenState extends State<WineDetailScreen> {
  final _repo = InventoryRepository.instance;
  Wine? _wine;
  int _stock = 0;
  List<Movement> _movements = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final wine = await _repo.wineById(widget.wineId);
    final stock = await _repo.stockForWine(widget.wineId);
    final movs = await _repo.movementsForWine(widget.wineId);
    if (!mounted) return;
    setState(() {
      _wine = wine;
      _stock = stock;
      _movements = movs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    final wine = _wine;
    if (wine == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Vino non trovato')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(wine.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => WineFormScreen(existing: wine)));
              _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: ListView(
        children: [
          if (wine.photoPath != null && File(wine.photoPath!).existsSync())
            Image.file(File(wine.photoPath!),
                height: 220, width: double.infinity, fit: BoxFit.cover),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(wine.label,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _stockBanner(),
                const SizedBox(height: 16),
                _infoTable(wine),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.shade700),
                        onPressed: () => _addMovement(MovementKind.inbound),
                        icon: const Icon(Icons.download),
                        label: const Text('Carico\n(compra)',
                            textAlign: TextAlign.center),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade700),
                        onPressed: _stock <= 0
                            ? null
                            : () => _addMovement(MovementKind.outbound),
                        icon: const Icon(Icons.upload),
                        label: const Text('Scarico\n(vendi)',
                            textAlign: TextAlign.center),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Storico movimenti',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
              ],
            ),
          ),
          if (_movements.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Nessun movimento ancora.')),
            )
          else
            ..._movements.map(_movementTile),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _stockBanner() {
    final low = _stock <= 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: low ? Colors.red.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(low ? Icons.warning_amber : Icons.check_circle,
              color: low ? Colors.red.shade700 : Colors.green.shade700),
          const SizedBox(width: 12),
          Text('Giacenza: ',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 16)),
          Text('$_stock bottiglie',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: low ? Colors.red.shade700 : Colors.green.shade700)),
        ],
      ),
    );
  }

  Widget _infoTable(Wine w) {
    final rows = <(String, String)>[
      if (w.type.isNotEmpty) ('Tipo', w.type),
      if (w.region.isNotEmpty) ('Regione', w.region),
      if (w.supplier.isNotEmpty) ('Fornitore', w.supplier),
      if (w.location.isNotEmpty) ('Posizione', w.location),
      if (w.priceBuy > 0) ('Prezzo acquisto', euro(w.priceBuy)),
      if (w.priceSell > 0) ('Prezzo vendita', euro(w.priceSell)),
      if (w.notes.isNotEmpty) ('Note', w.notes),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: rows
              .map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                            width: 130,
                            child: Text(r.$1,
                                style: TextStyle(
                                    color: Colors.grey.shade600))),
                        Expanded(
                            child: Text(r.$2,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500))),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _movementTile(Movement m) {
    final isIn = m.kind == MovementKind.inbound;
    return ListTile(
      leading: PhotoThumb(path: m.photoPath, size: 48),
      title: Text(
        '${isIn ? 'Carico' : 'Scarico'} di ${m.quantity} bottiglie',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${dateTime(m.createdAt)}'
        '${m.unitPrice > 0 ? ' · ${euro(m.unitPrice)}/cad' : ''}'
        '${m.note.isNotEmpty ? '\n${m.note}' : ''}',
      ),
      isThreeLine: m.note.isNotEmpty,
      trailing: Text(
        '${isIn ? '+' : '−'}${m.quantity}',
        style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isIn ? Colors.green.shade700 : Colors.red.shade700),
      ),
      onLongPress: () => _confirmDeleteMovement(m),
    );
  }

  Future<void> _addMovement(MovementKind kind) async {
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => MovementFormScreen(wine: _wine!, kind: kind)),
    );
    if (done == true) _load();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminare questo vino?'),
        content: const Text(
            'Verra\' rimosso dalla cantina insieme ai suoi movimenti.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Elimina')),
        ],
      ),
    );
    if (ok == true) {
      await _repo.softDeleteWine(widget.wineId);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _confirmDeleteMovement(Movement m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminare questo movimento?'),
        content: Text(
            '${m.kind == MovementKind.inbound ? 'Carico' : 'Scarico'} di ${m.quantity} bottiglie.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Elimina')),
        ],
      ),
    );
    if (ok == true) {
      await _repo.softDeleteMovement(m.id);
      _load();
    }
  }
}
