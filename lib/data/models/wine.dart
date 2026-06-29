/// Anagrafica di un vino in cantina.
///
/// Progettato per la sincronizzazione: ogni record ha un [id] univoco
/// (UUID) generato sul telefono, e un [updatedAt] usato per la fusione
/// "vince l'ultima modifica" (last-write-wins) quando due telefoni si
/// incontrano. [deleted] permette la cancellazione propagabile (soft delete).
class Wine {
  final String id;
  final String name;
  final String producer; // produttore / cantina
  final int? vintage; // annata (es. 2019)
  final String type; // Rosso, Bianco, Rosato, Bollicine, Dolce...
  final String region; // regione / denominazione
  final String supplier; // fornitore da cui si compra
  final String location; // posizione in cantina (scaffale, fila...)
  final double priceBuy; // prezzo di acquisto medio
  final double priceSell; // prezzo di vendita
  final String notes;
  final String? photoPath; // foto etichetta FRONTE (percorso locale)
  final String? photoPathBack; // foto etichetta RETRO (percorso locale)

  // Campi di sincronizzazione
  final int updatedAt; // millisecondi epoch dell'ultima modifica
  final bool deleted;

  const Wine({
    required this.id,
    required this.name,
    this.producer = '',
    this.vintage,
    this.type = '',
    this.region = '',
    this.supplier = '',
    this.location = '',
    this.priceBuy = 0,
    this.priceSell = 0,
    this.notes = '',
    this.photoPath,
    this.photoPathBack,
    required this.updatedAt,
    this.deleted = false,
  });

  Wine copyWith({
    String? name,
    String? producer,
    int? vintage,
    String? type,
    String? region,
    String? supplier,
    String? location,
    double? priceBuy,
    double? priceSell,
    String? notes,
    String? photoPath,
    bool clearPhoto = false,
    String? photoPathBack,
    bool clearPhotoBack = false,
    int? updatedAt,
    bool? deleted,
  }) {
    return Wine(
      id: id,
      name: name ?? this.name,
      producer: producer ?? this.producer,
      vintage: vintage ?? this.vintage,
      type: type ?? this.type,
      region: region ?? this.region,
      supplier: supplier ?? this.supplier,
      location: location ?? this.location,
      priceBuy: priceBuy ?? this.priceBuy,
      priceSell: priceSell ?? this.priceSell,
      notes: notes ?? this.notes,
      photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
      photoPathBack:
          clearPhotoBack ? null : (photoPathBack ?? this.photoPathBack),
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'producer': producer,
        'vintage': vintage,
        'type': type,
        'region': region,
        'supplier': supplier,
        'location': location,
        'price_buy': priceBuy,
        'price_sell': priceSell,
        'notes': notes,
        'photo_path': photoPath,
        'photo_path_back': photoPathBack,
        'updated_at': updatedAt,
        'deleted': deleted ? 1 : 0,
      };

  factory Wine.fromMap(Map<String, dynamic> m) => Wine(
        id: m['id'] as String,
        name: (m['name'] ?? '') as String,
        producer: (m['producer'] ?? '') as String,
        vintage: m['vintage'] as int?,
        type: (m['type'] ?? '') as String,
        region: (m['region'] ?? '') as String,
        supplier: (m['supplier'] ?? '') as String,
        location: (m['location'] ?? '') as String,
        priceBuy: (m['price_buy'] as num?)?.toDouble() ?? 0,
        priceSell: (m['price_sell'] as num?)?.toDouble() ?? 0,
        notes: (m['notes'] ?? '') as String,
        photoPath: m['photo_path'] as String?,
        photoPathBack: m['photo_path_back'] as String?,
        updatedAt: (m['updated_at'] as num?)?.toInt() ?? 0,
        deleted: (m['deleted'] as num?)?.toInt() == 1,
      );

  /// Versione "trasportabile" sulla rete / nel backup: la foto viaggia
  /// separatamente, qui resta solo il nome-file di riferimento.
  Map<String, dynamic> toSyncJson() => {
        ...toMap(),
        // sul filesystem il percorso e' assoluto e diverso su ogni telefono:
        // esportiamo solo il nome del file foto (fronte e retro).
        'photo_path': photoPath == null ? null : _basename(photoPath!),
        'photo_path_back':
            photoPathBack == null ? null : _basename(photoPathBack!),
      };

  static String _basename(String p) =>
      p.replaceAll('\\', '/').split('/').last;

  String get label {
    final v = vintage != null ? ' $vintage' : '';
    final p = producer.isNotEmpty ? ' · $producer' : '';
    return '$name$v'.trim() + p;
  }
}
