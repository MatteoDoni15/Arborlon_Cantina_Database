import 'package:flutter/material.dart';

import '../../data/models/movement.dart';
import '../../data/repositories/inventory_repository.dart';
import '../widgets/empty_state.dart';
import '../widgets/formatters.dart';
import '../widgets/photo_thumb.dart';
import 'settings_screen.dart';
import 'sync_screen.dart';
import 'wine_detail_screen.dart';
import 'wine_form_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repo = InventoryRepository.instance;
  String _search = '';

  String? _filterType;
  String? _filterGrape;
  String? _filterRegion;
  String? _filterDenomination;
  String? _filterCountry;

  int get _activeFilterCount => [
        _filterType,
        _filterGrape,
        _filterRegion,
        _filterDenomination,
        _filterCountry,
      ].where((v) => v != null).length;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cantina Vini'),
          actions: [
            IconButton(
              tooltip: 'Sincronizza',
              icon: const Icon(Icons.sync),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SyncScreen())),
            ),
            IconButton(
              tooltip: 'Impostazioni',
              icon: const Icon(Icons.settings),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'CANTINA', icon: Icon(Icons.wine_bar)),
              Tab(text: 'MOVIMENTI', icon: Icon(Icons.swap_vert)),
            ],
          ),
        ),
        body: AnimatedBuilder(
          animation: _repo,
          builder: (context, _) => TabBarView(
            children: [
              _buildCantina(),
              _buildMovimenti(),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addWine,
          icon: const Icon(Icons.add),
          label: const Text('Nuovo vino'),
        ),
      ),
    );
  }

  Future<void> _addWine() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const WineFormScreen()));
  }

  // -------------------------------------------------------------- CANTINA

  Widget _buildCantina() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Cerca per nome, produttore, regione...',
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 8),
              Badge(
                isLabelVisible: _activeFilterCount > 0,
                label: Text('$_activeFilterCount'),
                child: IconButton.filledTonal(
                  tooltip: 'Filtra',
                  icon: const Icon(Icons.filter_list),
                  onPressed: _openFilterSheet,
                ),
              ),
            ],
          ),
        ),
        _activeFilterChips(),
        Expanded(
          child: FutureBuilder<List<WineWithStock>>(
            future: _repo.winesWithStock(
              search: _search,
              type: _filterType,
              grape: _filterGrape,
              region: _filterRegion,
              denomination: _filterDenomination,
              country: _filterCountry,
            ),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snap.data!;
              if (items.isEmpty) {
                return const EmptyState(
                  icon: Icons.wine_bar,
                  title: 'Cantina vuota',
                  message:
                      'Aggiungi il primo vino con il pulsante "Nuovo vino".',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _WineCard(
                  item: items[i],
                  onTap: () => _openWine(items[i].wine.id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openWine(String id) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => WineDetailScreen(wineId: id)));
  }

  /// Chip dei filtri attivi, ognuno rimovibile singolarmente.
  Widget _activeFilterChips() {
    final chips = <Widget>[
      if (_filterType != null)
        _filterChip('Tipo: $_filterType', () => setState(() => _filterType = null)),
      if (_filterGrape != null)
        _filterChip('Uvaggio: $_filterGrape', () => setState(() => _filterGrape = null)),
      if (_filterRegion != null)
        _filterChip('Regione: $_filterRegion', () => setState(() => _filterRegion = null)),
      if (_filterDenomination != null)
        _filterChip('Denominazione: $_filterDenomination',
            () => setState(() => _filterDenomination = null)),
      if (_filterCountry != null)
        _filterChip('Stato: $_filterCountry', () => setState(() => _filterCountry = null)),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Wrap(spacing: 8, runSpacing: 4, children: chips),
    );
  }

  Widget _filterChip(String label, VoidCallback onRemoved) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onDeleted: onRemoved,
      visualDensity: VisualDensity.compact,
    );
  }

  /// Apre il pannello dei filtri: uvaggio, regione, denominazione, stato e
  /// tipo, ognuno popolato con i soli valori gia' presenti in cantina.
  Future<void> _openFilterSheet() async {
    final options = await Future.wait([
      _repo.distinctWineValues('type'),
      _repo.distinctWineValues('grape'),
      _repo.distinctWineValues('region'),
      _repo.distinctWineValues('denomination'),
      _repo.distinctWineValues('country'),
    ]);
    if (!mounted) return;

    String? type = _filterType;
    String? grape = _filterGrape;
    String? region = _filterRegion;
    String? denomination = _filterDenomination;
    String? country = _filterCountry;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Text('Filtra cantina',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 18)),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setSheetState(() {
                            type = null;
                            grape = null;
                            region = null;
                            denomination = null;
                            country = null;
                          }),
                          child: const Text('Azzera'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _filterDropdown('Tipo', type, options[0],
                        (v) => setSheetState(() => type = v)),
                    const SizedBox(height: 12),
                    _filterDropdown('Uvaggio', grape, options[1],
                        (v) => setSheetState(() => grape = v)),
                    const SizedBox(height: 12),
                    _filterDropdown('Regione', region, options[2],
                        (v) => setSheetState(() => region = v)),
                    const SizedBox(height: 12),
                    _filterDropdown('Denominazione', denomination, options[3],
                        (v) => setSheetState(() => denomination = v)),
                    const SizedBox(height: 12),
                    _filterDropdown('Stato', country, options[4],
                        (v) => setSheetState(() => country = v)),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Applica filtri'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    setState(() {
      _filterType = type;
      _filterGrape = grape;
      _filterRegion = region;
      _filterDenomination = denomination;
      _filterCountry = country;
    });
  }

  Widget _filterDropdown(String label, String? value, List<String> options,
      ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String?>(
      value: value,
      decoration: InputDecoration(
          labelText: label, border: const OutlineInputBorder()),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Tutti')),
        ...options.map(
            (o) => DropdownMenuItem<String?>(value: o, child: Text(o))),
      ],
      onChanged: onChanged,
    );
  }

  // ------------------------------------------------------------ MOVIMENTI

  Widget _buildMovimenti() {
    return FutureBuilder<List<Movement>>(
      future: _repo.recentMovements(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final movs = snap.data!;
        if (movs.isEmpty) {
          return const EmptyState(
            icon: Icons.swap_vert,
            title: 'Nessun movimento',
            message:
                'I carichi (acquisti) e gli scarichi (vendite) appariranno qui.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: movs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) => _MovementRow(movement: movs[i]),
        );
      },
    );
  }
}

class _WineCard extends StatelessWidget {
  final WineWithStock item;
  final VoidCallback onTap;

  const _WineCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final wine = item.wine;
    final stock = item.stock;
    final lowStock = stock <= 0;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              PhotoThumb(path: wine.photoPath, size: 60),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(wine.label,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (wine.type.isNotEmpty) wine.type,
                        if (wine.region.isNotEmpty) wine.region,
                        if (wine.location.isNotEmpty) '📍 ${wine.location}',
                      ].join(' · '),
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: lowStock
                          ? Colors.red.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$stock',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: lowStock
                            ? Colors.red.shade700
                            : Colors.green.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('bottiglie',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  final Movement movement;
  const _MovementRow({required this.movement});

  @override
  Widget build(BuildContext context) {
    final isIn = movement.kind == MovementKind.inbound;
    return FutureBuilder(
      future: InventoryRepository.instance.wineById(movement.wineId),
      builder: (context, snap) {
        final wineName = snap.data?.label ?? '...';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: PhotoThumb(path: movement.photoPath, size: 48),
          title: Text(wineName,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(dateTime(movement.createdAt)),
          trailing: Text(
            '${isIn ? '+' : '−'}${movement.quantity}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isIn ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ),
        );
      },
    );
  }
}
