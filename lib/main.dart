import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'data/db/app_database.dart';
import 'services/device_service.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Carica i formati italiani di date e valuta.
  await initializeDateFormatting('it_IT', null);
  // Prepara DB e identita' del telefono prima di partire.
  await AppDatabase.instance.database;
  await DeviceService.instance.deviceId();
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
