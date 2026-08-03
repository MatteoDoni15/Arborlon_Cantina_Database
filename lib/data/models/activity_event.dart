/// Un evento del registro attività: "chi ha fatto cosa e quando".
///
/// Non è una tabella a sé: viene ricostruito al volo leggendo vini e
/// movimenti (che già portano l'autore), così non c'è un log separato da
/// tenere sincronizzato.
enum ActivityType { wineAdded, wineEdited, movementIn, movementOut }

class ActivityEvent {
  final ActivityType type;
  final int at; // millisecondi epoch
  final String wineId;
  final String wineLabel;
  final String author;
  final int quantity; // bottiglie, solo per i movimenti
  final double unitPrice; // solo per i movimenti
  final String note;

  const ActivityEvent({
    required this.type,
    required this.at,
    required this.wineId,
    required this.wineLabel,
    required this.author,
    this.quantity = 0,
    this.unitPrice = 0,
    this.note = '',
  });

  /// Nome autore leggibile: i dati precedenti all'introduzione del registro
  /// non hanno un autore noto.
  String get authorLabel => author.isEmpty ? 'Sconosciuto' : author;
}
