import '../sync/cloud_sync_service.dart';
import 'device_service.dart';

/// Nome "autore" da registrare nei log delle attività (chi ha aggiunto un
/// vino, chi ha venduto/caricato bottiglie...).
///
/// Non esiste un login personale obbligatorio: se il cloud premium è attivo
/// e l'utente ha fatto login, usiamo la sua email (identifica la persona).
/// Altrimenti ricadiamo sul nome del telefono impostato in Impostazioni
/// (es. "Sala", "Bar"), che resta comunque leggibile per i colleghi.
class ActivityAuthor {
  static Future<String> current() async {
    final email = CloudSyncService.instance.currentEmail;
    if (email != null && email.isNotEmpty) return email;
    return DeviceService.instance.deviceName();
  }
}
