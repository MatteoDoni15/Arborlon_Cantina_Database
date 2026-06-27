/// Movimento di magazzino: un CARICO (acquisto) o uno SCARICO (vendita).
///
/// I movimenti sono *eventi*: una volta registrati non cambiano. Questo
/// rende la sincronizzazione banale e senza conflitti: unire due telefoni
/// = unione delle liste di movimenti per [id]. La giacenza di un vino e'
/// sempre ricalcolata sommando i carichi e sottraendo gli scarichi.
enum MovementKind { inbound, outbound }

extension MovementKindX on MovementKind {
  String get db => this == MovementKind.inbound ? 'in' : 'out';
  String get labelIt => this == MovementKind.inbound ? 'Carico' : 'Scarico';
  static MovementKind fromDb(String v) =>
      v == 'in' ? MovementKind.inbound : MovementKind.outbound;
}

class Movement {
  final String id;
  final String wineId;
  final MovementKind kind;
  final int quantity; // numero di bottiglie (sempre positivo)
  final double unitPrice; // prezzo unitario di questo movimento
  final String note;
  final String? photoPath; // foto scattata al momento di compra/vendita
  final String deviceId; // telefono che ha registrato il movimento

  final int createdAt; // quando e' avvenuto il movimento
  final int updatedAt; // per la fusione (LWW) in caso di correzioni
  final bool deleted;

  const Movement({
    required this.id,
    required this.wineId,
    required this.kind,
    required this.quantity,
    this.unitPrice = 0,
    this.note = '',
    this.photoPath,
    required this.deviceId,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  /// Variazione sulla giacenza: +q per i carichi, -q per gli scarichi.
  int get signedQuantity =>
      kind == MovementKind.inbound ? quantity : -quantity;

  Movement copyWith({
    int? quantity,
    double? unitPrice,
    String? note,
    String? photoPath,
    bool clearPhoto = false,
    int? updatedAt,
    bool? deleted,
  }) {
    return Movement(
      id: id,
      wineId: wineId,
      kind: kind,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      note: note ?? this.note,
      photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
      deviceId: deviceId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'wine_id': wineId,
        'kind': kind.db,
        'quantity': quantity,
        'unit_price': unitPrice,
        'note': note,
        'photo_path': photoPath,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted': deleted ? 1 : 0,
      };

  factory Movement.fromMap(Map<String, dynamic> m) => Movement(
        id: m['id'] as String,
        wineId: m['wine_id'] as String,
        kind: MovementKindX.fromDb((m['kind'] ?? 'in') as String),
        quantity: (m['quantity'] as num?)?.toInt() ?? 0,
        unitPrice: (m['unit_price'] as num?)?.toDouble() ?? 0,
        note: (m['note'] ?? '') as String,
        photoPath: m['photo_path'] as String?,
        deviceId: (m['device_id'] ?? '') as String,
        createdAt: (m['created_at'] as num?)?.toInt() ?? 0,
        updatedAt: (m['updated_at'] as num?)?.toInt() ?? 0,
        deleted: (m['deleted'] as num?)?.toInt() == 1,
      );

  Map<String, dynamic> toSyncJson() => {
        ...toMap(),
        'photo_path': photoPath == null ? null : _basename(photoPath!),
      };

  static String _basename(String p) =>
      p.replaceAll('\\', '/').split('/').last;
}
