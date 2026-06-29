import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/db/app_database.dart';
import 'services/app_settings.dart';
import 'services/device_service.dart';
import 'sync/cloud_config.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Carica i formati italiani di date e valuta.
  await initializeDateFormatting('it_IT', null);
  // Prepara DB e identita' del telefono prima di partire.
  await AppDatabase.instance.database;
  await DeviceService.instance.deviceId();
  // Preferenze freemium (modalita' sync, premium, codice ristorante).
  await AppSettings.instance.load();
  // Cloud (Fase 2): si inizializza SOLO se le chiavi sono presenti. Senza,
  // l'app resta 100% locale + P2P, esattamente come prima.
  if (CloudConfig.isConfigured) {
    await Supabase.initialize(
      url: CloudConfig.supabaseUrl,
      anonKey: CloudConfig.supabaseAnonKey,
    );
  }
  runApp(const CantinaApp());
}

class CantinaApp extends StatelessWidget {
  const CantinaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cantina Vini',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const HomeScreen(),
    );
  }
}
