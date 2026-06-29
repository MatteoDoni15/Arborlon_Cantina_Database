/// Credenziali del progetto Supabase (Fase 2 — cloud premium).
///
/// Si compilano da riga di comando senza toccare il codice, così le chiavi
/// non finiscono nel repository:
///
/// ```powershell
/// flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co ^
///             --dart-define=SUPABASE_ANON_KEY=eyJhbGci...
/// ```
///
/// In alternativa, per provare in fretta, puoi incollarle nei [defaultValue].
/// Finché non sono valorizzate, l'app funziona normalmente in locale + P2P:
/// la sezione cloud nelle impostazioni resta semplicemente disabilitata.
class CloudConfig {
  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');

  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// Bucket dello Storage Supabase dove vivono le foto delle etichette.
  static const String photosBucket = 'photos';

  /// True solo se le chiavi sono presenti: in caso contrario il cloud è
  /// inattivo e l'app resta 100% locale + P2P.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
