import 'dart:math' as math;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'dictionary_service.dart';
import 'text_normalizer.dart';

/// Lettura del testo dall'etichetta (OCR) per precompilare i campi del vino.
///
/// E' un aiuto opzionale: l'utente puo' sempre correggere a mano. Tutto
/// avviene sul telefono, senza internet.
///
/// Si possono passare entrambe le foto (fronte e retro): il nome si cerca sul
/// fronte, mentre il retro serve a confermarlo e a ricavare produttore
/// ("imbottigliato da..."), denominazione/regione e annata.
///
/// Il nome viene proposto come lista di candidati ordinata dal piu' probabile
/// al meno probabile, combinando tre segnali:
///  - la GEOMETRIA: sulle etichette il nome e' quasi sempre la scritta con i
///    caratteri piu' grandi (altezza del boundingBox), non la piu' lunga;
///  - la CANTINA: se una riga somiglia al nome di un vino gia' inserito nel
///    database, quel nome viene promosso e proposto nella forma gia' salvata;
///  - il DIZIONARIO (denominazioni + vini noti, vedi DictionaryService):
///    conferma piu' debole della cantina, ma copre anche i vini mai inseriti.
class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Righe che non possono essere il nome: gradazione, volume, diciture
  /// legali, contatti. Vengono scartate del tutto (solo come nome: le stesse
  /// righe restano disponibili per estrarre produttore e denominazione).
  static final _noisePatterns = <RegExp>[
    RegExp(r'\d+[.,]?\d*\s*%'), // 13,5%
    RegExp(r'\b\d+[.,]?\d*\s*(cl|ml|litri?|l)\b', caseSensitive: false),
    RegExp(r'\b(vol|alc)\b\.?', caseSensitive: false),
    RegExp(r'imbottigliat|prodott[oa]\s+|bottled|produced\s+by',
        caseSensitive: false),
    RegExp(r'solfiti|sulfites|sulphites|allergen', caseSensitive: false),
    RegExp(r'www\.|http|@'),
    RegExp(r'\bs\.?r\.?l\b|\bs\.?p\.?a\b', caseSensitive: false),
  ];

  /// Parole "di servizio" (denominazioni, diciture generiche): una riga fatta
  /// SOLO di queste non e' un nome ("Denominazione di Origine Controllata").
  /// Se invece compaiono dentro un nome vero ("Vino Nobile di Montepulciano")
  /// la riga sopravvive, perche' contiene anche parole fuori da questa lista.
  static const _fillerWords = <String>{
    'denominazione', 'origine', 'controllata', 'garantita', 'indicazione',
    'geografica', 'tipica', 'protetta', 'doc', 'docg', 'dop', 'igt', 'igp',
    'vino', 'vini', 'wine', 'product', 'of', 'italy', 'italia', 'italie',
    'france', 'di', 'e', 'del', 'della', 'dei', 'delle',
  };

  /// Sigle di denominazione: una riga che ne contiene una insieme ad altre
  /// parole "vere" ("Chianti Classico DOCG") e' la denominazione del vino.
  static const _denomWords = <String>{
    'doc', 'docg', 'dop', 'igt', 'igp', 'aoc', 'aop',
  };

  /// Regioni riconosciute nel testo (forma normalizzata -> forma da mostrare).
  static const _regions = <String, String>{
    'piemonte': 'Piemonte', 'toscana': 'Toscana', 'veneto': 'Veneto',
    'lombardia': 'Lombardia', 'sicilia': 'Sicilia', 'puglia': 'Puglia',
    'abruzzo': 'Abruzzo', 'marche': 'Marche', 'umbria': 'Umbria',
    'lazio': 'Lazio', 'campania': 'Campania', 'basilicata': 'Basilicata',
    'calabria': 'Calabria', 'sardegna': 'Sardegna', 'liguria': 'Liguria',
    'molise': 'Molise', 'trentino': 'Trentino', 'alto adige': 'Alto Adige',
    'sudtirol': 'Alto Adige', 'friuli': 'Friuli-Venezia Giulia',
    'emilia': 'Emilia-Romagna', 'romagna': 'Emilia-Romagna',
    'valle d aosta': "Valle d'Aosta",
  };

  /// Risultato grezzo: tutte le righe di testo trovate sull'etichetta.
  Future<List<String>> readLines(String imagePath) async {
    final scan = await _scan(imagePath);
    return scan.lines;
  }

  /// Estrae annata, produttore, regione/denominazione e una lista di possibili
  /// nomi dal piu' probabile al meno probabile.
  ///
  /// [imagePath] e' l'etichetta fronte; [backImagePath], se presente, il retro.
  /// [knownNames] sono i nomi dei vini gia' in cantina: se una riga letta
  /// somiglia a uno di questi, il candidato viene rafforzato e proposto
  /// nella forma esatta gia' salvata (cosi' l'OCR "sbagliato" si autocorregge).
  /// [dictionary] sono le voci del dizionario nomi (DictionaryService):
  /// rafforzano il candidato (meno della cantina) e portano in dote
  /// produttore e regione suggeriti.
  Future<OcrGuess> guessWine(
    String imagePath, {
    String? backImagePath,
    List<String> knownNames = const [],
    List<WineDictEntry> dictionary = const [],
  }) async {
    final front = await _scan(imagePath);
    final back = backImagePath == null ? null : await _scan(backImagePath);
    final scans = [front, if (back != null) back];

    // ---- Annata: un anno plausibile, prima sul fronte poi sul retro.
    int? vintage;
    final yearRe = RegExp(r'\b(19|20)\d{2}\b');
    outer:
    for (final s in scans) {
      for (final l in s.lines) {
        final m = yearRe.firstMatch(l);
        if (m != null) {
          final y = int.parse(m.group(0)!);
          if (y >= 1900 && y <= DateTime.now().year + 1) {
            vintage = y;
            break outer;
          }
        }
      }
    }

    final producer = _findProducer(scans);
    final region = _findRegion(scans);

    // ---- Candidati nome: solo dal fronte (il nome sta li'), con punteggio
    // geometrico: altezza dei caratteri (peso dominante) + quantita' di
    // lettere (per non premiare righe minuscole o solo numeri).
    final maxH = front.blocks
        .expand((b) => b)
        .fold(0.0, (m, l) => math.max(m, l.height));
    final candidates = <String, OcrCandidate>{}; // testo normalizzato -> best

    void addCandidate(OcrCandidate c) {
      if (c.score <= 0) return;
      final key = normalizeWineText(c.text);
      if (key.isEmpty) return;
      final existing = candidates[key];
      if (existing == null || c.score > existing.score) {
        candidates[key] = c;
      }
    }

    double baseScore(String text, double height) {
      final letters = normalizeWineText(text).replaceAll(RegExp(r'[^a-z]'), '');
      if (letters.length < 3) return 0;
      final rel = maxH > 0 ? height / maxH : 0.0;
      final letterScore = math.min(letters.length, 14) / 14.0;
      return 0.65 * rel + 0.35 * letterScore;
    }

    for (final block in front.blocks) {
      _Line? prev; // riga precedente non-rumore, per i nomi su due righe
      for (final line in block) {
        if (_isNoise(line.text)) {
          prev = null;
          continue;
        }
        addCandidate(OcrCandidate(
            text: line.text, score: baseScore(line.text, line.height)));
        // Un nome spezzato su due righe e' scritto grande su entrambe.
        // Piccolo sconto per preferire la riga singola a parita' di punteggio.
        if (prev != null && math.min(prev.height, line.height) >= 0.6 * maxH) {
          final joined = '${prev.text} ${line.text}';
          addCandidate(OcrCandidate(
              text: joined,
              score:
                  baseScore(joined, math.max(prev.height, line.height)) * 0.95));
        }
        prev = line;
      }
    }

    // ---- Il retro conferma: un nome che compare su entrambe le etichette
    // e' quasi certamente quello giusto.
    if (back != null) {
      final backNorm = [for (final l in back.lines) normalizeWineText(l)];
      for (final e in candidates.entries.toList()) {
        final onBack =
            backNorm.any((b) => wineTextSimilarity(e.key, b) >= 0.85);
        if (onBack) {
          candidates[e.key] =
              e.value.copyWith(score: math.min(1.0, e.value.score + 0.1));
        }
      }
    }

    // ---- Confronto col DIZIONARIO: conferma il candidato (bonus moderato)
    // e porta in dote produttore/regione da suggerire nel form.
    if (dictionary.isNotEmpty) {
      final dictNorm = [
        for (final e in dictionary) (normalizeWineText(e.name), e),
      ];
      // Con dizionari grandi si confrontano solo le voci che condividono un
      // prefisso di parola col candidato, per restare veloci.
      Map<String, List<(String, WineDictEntry)>>? index;
      if (dictNorm.length > 1500) {
        index = {};
        for (final d in dictNorm) {
          for (final t in d.$1.split(' ')) {
            if (t.length >= 4) (index[t.substring(0, 4)] ??= []).add(d);
          }
        }
      }
      for (final c in candidates.values.toList()) {
        final normC = normalizeWineText(c.text);
        Iterable<(String, WineDictEntry)> pool = dictNorm;
        if (index != null) {
          final shortlist = <(String, WineDictEntry)>{};
          for (final t in normC.split(' ')) {
            if (t.length >= 4) {
              shortlist.addAll(index[t.substring(0, 4)] ?? const []);
            }
          }
          pool = shortlist;
        }
        double best = 0;
        WineDictEntry? bestEntry;
        for (final d in pool) {
          final sim = wineTextSimilarity(normC, d.$1);
          if (sim > best) {
            best = sim;
            bestEntry = d.$2;
          }
        }
        if (best >= 0.72 && bestEntry != null) {
          addCandidate(OcrCandidate(
            text: bestEntry.name,
            score: math.min(1.0, c.score + 0.25 * best),
            fromDictionary: true,
            producer: bestEntry.producer,
            region: bestEntry.region,
          ));
        }
      }
    }

    // ---- Confronto con la CANTINA: e' il segnale piu' forte (quel vino lo
    // compri davvero). Sostituisce il testo con la forma gia' salvata.
    final known = <String, String>{}; // normalizzato -> forma originale
    for (final n in knownNames) {
      final key = normalizeWineText(n);
      if (key.length >= 3) known.putIfAbsent(key, () => n.trim());
    }
    if (known.isNotEmpty) {
      for (final c in candidates.values.toList()) {
        final normC = normalizeWineText(c.text);
        double best = 0;
        String? bestName;
        for (final e in known.entries) {
          final sim = wineTextSimilarity(normC, e.key);
          if (sim > best) {
            best = sim;
            bestName = e.value;
          }
        }
        if (best >= 0.72 && bestName != null) {
          addCandidate(OcrCandidate(
            text: bestName,
            score: math.min(1.0, c.score + 0.4 * best),
            fromCellar: true,
          ));
        }
      }
    }

    final ranked = candidates.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return OcrGuess(
      candidates: ranked.take(5).toList(),
      vintage: vintage,
      producer: producer,
      region: region,
      allLines: [for (final s in scans) ...s.lines],
    );
  }

  /// Legge un'immagine e restituisce le righe raggruppate per blocco,
  /// con l'altezza dei caratteri di ciascuna.
  Future<_Scan> _scan(String imagePath) async {
    final input = InputImage.fromFilePath(imagePath);
    final result = await _recognizer.processImage(input);
    final lines = <String>[];
    final blocks = <List<_Line>>[];
    for (final block in result.blocks) {
      final rows = <_Line>[];
      for (final line in block.lines) {
        final t = line.text.trim();
        if (t.isEmpty) continue;
        lines.add(t);
        rows.add(_Line(t, line.boundingBox.height.toDouble()));
      }
      if (rows.isNotEmpty) blocks.add(rows);
    }
    return _Scan(lines, blocks);
  }

  /// Produttore: prima "imbottigliato/prodotto da X" (il nome e' sulla stessa
  /// riga dopo il "da", oppure sulla riga subito sotto), poi righe che
  /// iniziano con "Azienda Agricola", "Tenuta", "Cantina"...
  String _findProducer(List<_Scan> scans) {
    final keywordRe =
        RegExp(r'imbottigliat|prodott|vinificat|bottled|produced');
    final daRe = RegExp(r'\b(da|dal|dalla|dall|by)\b');
    for (final s in scans) {
      for (final block in s.blocks) {
        for (var i = 0; i < block.length; i++) {
          final line = block[i].text;
          final low = line.toLowerCase();
          final kw = keywordRe.firstMatch(low);
          if (kw == null) continue;
          Match? da;
          for (final m in daRe.allMatches(low)) {
            if (m.start >= kw.start) {
              da = m;
              break;
            }
          }
          if (da != null) {
            final rest = line.substring(da.end).trim();
            if (_looksLikeProducer(rest)) return _cleanProducer(rest);
          }
          // "Imbottigliato da" a fine riga: il nome e' sulla riga sotto.
          if (i + 1 < block.length && _looksLikeProducer(block[i + 1].text)) {
            return _cleanProducer(block[i + 1].text);
          }
        }
      }
    }
    final prefixRe = RegExp(
        r'^(azienda agricola|societa agricola|az agr|soc agr|tenuta|tenute|'
        r'cantina|cantine|podere|poderi|fattoria|castello|abbazia|marchesi)\b');
    for (final s in scans) {
      for (final l in s.lines) {
        if (prefixRe.hasMatch(normalizeWineText(l))) return _cleanProducer(l);
      }
    }
    return '';
  }

  /// Scarta resti tipo "uve Sangiovese" (dopo "prodotto da uve...").
  bool _looksLikeProducer(String s) {
    final norm = normalizeWineText(s);
    final letters = norm.replaceAll(RegExp(r'[^a-z]'), '');
    if (letters.length < 3) return false;
    const notNames = {'uve', 'uva', 'vigne', 'vigneti', 'agricoltura', 'mosto'};
    final first = norm.split(' ').first;
    return !notNames.contains(first);
  }

  /// Toglie indirizzi e code: tiene la parte prima di " - ", limita la
  /// lunghezza, pulisce punteggiatura ai bordi.
  String _cleanProducer(String s) {
    var t = s.split(RegExp(r'\s+[-–|;•]\s+')).first;
    t = t.replaceAll(RegExp(r"^[',.\s]+|[',.\s]+$"), '');
    if (t.length > 60) {
      final cut = t.substring(0, 60);
      final sp = cut.lastIndexOf(' ');
      t = sp > 20 ? cut.substring(0, sp) : cut;
    }
    return t;
  }

  /// Regione/denominazione: prima una riga di denominazione con parole "vere"
  /// ("Chianti Classico DOCG"), poi una regione citata nel testo.
  String _findRegion(List<_Scan> scans) {
    for (final s in scans) {
      for (final l in s.lines) {
        final tokens = normalizeWineText(l).split(' ');
        final hasDenom = tokens.any(_denomWords.contains);
        final hasRealWord = tokens.any((w) =>
            w.isNotEmpty &&
            !_fillerWords.contains(w) &&
            !RegExp(r'^\d+$').hasMatch(w));
        if (hasDenom && hasRealWord) return l.trim();
      }
    }
    for (final s in scans) {
      for (final l in s.lines) {
        final norm = ' ${normalizeWineText(l)} ';
        for (final e in _regions.entries) {
          if (norm.contains(' ${e.key} ')) return e.value;
        }
      }
    }
    return '';
  }

  bool _isNoise(String t) {
    for (final re in _noisePatterns) {
      if (re.hasMatch(t)) return true;
    }
    final tokens = normalizeWineText(t).split(' ').where((w) => w.isNotEmpty);
    if (tokens.isEmpty) return true;
    return tokens.every(
        (w) => _fillerWords.contains(w) || RegExp(r'^\d+$').hasMatch(w));
  }

  void dispose() => _recognizer.close();
}

/// Una riga di testo letta, con l'altezza dei caratteri in pixel.
class _Line {
  final String text;
  final double height;
  const _Line(this.text, this.height);
}

/// Il testo di un'immagine: righe in ordine, raggruppate per blocco.
class _Scan {
  final List<String> lines;
  final List<List<_Line>> blocks;
  const _Scan(this.lines, this.blocks);
}

/// Un possibile nome del vino, con quanto il servizio ci "crede" (0..1).
/// [fromCellar] = corrisponde a un vino gia' presente nel database;
/// [fromDictionary] = corrisponde a una voce del dizionario nomi, e in quel
/// caso [producer]/[region] portano i suggerimenti della voce ('' se niente).
class OcrCandidate {
  final String text;
  final double score;
  final bool fromCellar;
  final bool fromDictionary;
  final String producer;
  final String region;
  const OcrCandidate({
    required this.text,
    required this.score,
    this.fromCellar = false,
    this.fromDictionary = false,
    this.producer = '',
    this.region = '',
  });

  OcrCandidate copyWith({double? score}) => OcrCandidate(
        text: text,
        score: score ?? this.score,
        fromCellar: fromCellar,
        fromDictionary: fromDictionary,
        producer: producer,
        region: region,
      );
}

class OcrGuess {
  /// Candidati nome, dal piu' probabile al meno probabile (max 5).
  final List<OcrCandidate> candidates;
  final int? vintage;
  final String producer; // '' se non trovato
  final String region; // regione o denominazione, '' se non trovata
  final List<String> allLines;
  const OcrGuess({
    required this.candidates,
    required this.vintage,
    this.producer = '',
    this.region = '',
    required this.allLines,
  });

  /// Il candidato migliore (compatibilita' col codice esistente).
  String get name => candidates.isEmpty ? '' : candidates.first.text;

  bool get isEmpty =>
      candidates.isEmpty && vintage == null && producer.isEmpty &&
      region.isEmpty;
}
