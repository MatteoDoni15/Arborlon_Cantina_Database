import 'package:uuid/uuid.dart';

import '../data/db/app_database.dart';

/// Identita' del telefono. Ogni dispositivo ha un id stabile (generato una
/// volta sola) e un nome leggibile mostrato durante la sincronizzazione.
class DeviceService {
  DeviceService._();
  static final DeviceService instance = DeviceService._();

  final _db = AppDatabase.instance;
  String? _deviceId;

  Future<String> deviceId() async {
    if (_deviceId != null) return _deviceId!;
    var id = await _db.getMeta('device_id');
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await _db.setMeta('device_id', id);
    }
    _deviceId = id;
    return id;
  }

  Future<String> deviceName() async {
    final n = await _db.getMeta('device_name');
    if (n != null && n.isNotEmpty) return n;
    final id = await deviceId();
    return 'Telefono-${id.substring(0, 4)}';
  }

  Future<void> setDeviceName(String name) async {
    await _db.setMeta('device_name', name.trim());
  }
}
