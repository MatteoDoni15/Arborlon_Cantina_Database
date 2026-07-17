import 'dart:math' as math;

/// Normalizzazione e confronto dei testi "da etichetta" (nomi di vino,
/// produttori). Usata sia dall'OCR sia dal dizionario dei nomi.
///
/// ATTENZIONE: la funzione `dict_norm` in supabase/dizionario-vini.sql fa la
/// stessa normalizzazione lato server: se cambi qui, cambia anche la'.

/// minuscolo, senza accenti ne' punteggiatura, spazi singoli.
String normalizeWineText(String s) {
  var t = s.toLowerCase();
  const accents = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
  };
  accents.forEach((k, v) => t = t.replaceAll(k, v));
  t = t.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Somiglianza tra due testi GIA' normalizzati: 1.0 = identici, 0.0 = niente
/// in comune. Il contenimento conta quasi come un match pieno: "sassicaia"
/// dentro "tenuta san guido sassicaia".
double wineTextSimilarity(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 1;
  if (a.length >= 5 && b.contains(a)) return 0.9;
  if (b.length >= 5 && a.contains(b)) return 0.9;
  final d = _levenshtein(a, b);
  return 1 - d / math.max(a.length, b.length);
}

int _levenshtein(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var cur = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] =
          math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
    }
    final tmp = prev;
    prev = cur;
    cur = tmp;
  }
  return prev[b.length];
}
