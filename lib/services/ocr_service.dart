import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Lettura del testo dall'etichetta (OCR) per precompilare i campi del vino.
///
/// E' un aiuto opzionale: l'utente puo' sempre correggere a mano. Tutto
/// avviene sul telefono, senza internet.
class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Risultato grezzo: tutte le righe di testo trovate sull'etichetta.
  Future<List<String>> readLines(String imagePath) async {
    final input = InputImage.fromFilePath(imagePath);
    final result = await _recognizer.processImage(input);
    final lines = <String>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        final t = line.text.trim();
        if (t.isNotEmpty) lines.add(t);
      }
    }
    return lines;
  }

  /// Tentativo "best effort" di estrarre nome e annata dall'etichetta.
  Future<OcrGuess> guessWine(String imagePath) async {
    final lines = await readLines(imagePath);

    int? vintage;
    final yearRe = RegExp(r'\b(19|20)\d{2}\b');
    for (final l in lines) {
      final m = yearRe.firstMatch(l);
      if (m != null) {
        final y = int.tryParse(m.group(0)!);
        if (y != null && y >= 1900 && y <= DateTime.now().year + 1) {
          vintage = y;
          break;
        }
      }
    }

    // Euristica semplice: la riga piu' lunga in lettere e' spesso il nome.
    String name = '';
    int best = 0;
    for (final l in lines) {
      final letters = l.replaceAll(RegExp(r'[^A-Za-zÀ-ÿ ]'), '').trim();
      if (letters.length > best && letters.length >= 3) {
        best = letters.length;
        name = l.trim();
      }
    }

    return OcrGuess(name: name, vintage: vintage, allLines: lines);
  }

  void dispose() => _recognizer.close();
}

class OcrGuess {
  final String name;
  final int? vintage;
  final List<String> allLines;
  const OcrGuess({
    required this.name,
    required this.vintage,
    required this.allLines,
  });
}
