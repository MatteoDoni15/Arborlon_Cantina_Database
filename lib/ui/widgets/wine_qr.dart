import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/models/wine.dart';

/// Codifica/decodifica del QR con l'anagrafica di un vino.
///
/// Serve per due usi complementari:
///  - STAMPA: si genera il QR di un vino gia' in cantina, da incollare sulla
///    bottiglia (utile per i vini che non hanno gia' un codice loro).
///  - LETTURA: in fase di inserimento, se la bottiglia ha gia' un QR di
///    questo formato (stampato da questa cantina o da un'altra), lo si
///    inquadra e i campi si riempiono da soli, senza foto ne' OCR.
///
/// Prefisso testuale dedicato (diverso da CANTINA-INVITE: e dal JSON della
/// sync P2P) cosi' i vari scanner dell'app non si confondono a vicenda.
/// Chiavi JSON abbreviate per tenere il QR piu' leggero (piu' denso di dati
/// = piu' difficile da leggere per la fotocamera).
class WineQrCodec {
  static const _prefix = 'CANTINA-WINE:';

  static String encode(Wine wine) {
    final map = <String, dynamic>{
      'n': wine.name,
      if (wine.producer.isNotEmpty) 'p': wine.producer,
      if (wine.vintage != null) 'v': wine.vintage,
      if (wine.type.isNotEmpty) 't': wine.type,
      if (wine.grape.isNotEmpty) 'g': wine.grape,
      if (wine.region.isNotEmpty) 'r': wine.region,
      if (wine.denomination.isNotEmpty) 'd': wine.denomination,
      if (wine.country.isNotEmpty) 'c': wine.country,
    };
    return '$_prefix${jsonEncode(map)}';
  }

  /// Ritorna i dati letti se [raw] e' un QR vino di questo formato,
  /// altrimenti null (es. e' un codice a barre qualunque, o un QR di invito).
  static WineQrData? tryDecode(String raw) {
    final s = raw.trim();
    if (!s.startsWith(_prefix)) return null;
    try {
      final map = jsonDecode(s.substring(_prefix.length)) as Map;
      final name = (map['n'] as String?)?.trim() ?? '';
      if (name.isEmpty) return null;
      return WineQrData(
        name: name,
        producer: (map['p'] as String?)?.trim() ?? '',
        vintage: (map['v'] as num?)?.toInt(),
        type: (map['t'] as String?)?.trim() ?? '',
        grape: (map['g'] as String?)?.trim() ?? '',
        region: (map['r'] as String?)?.trim() ?? '',
        denomination: (map['d'] as String?)?.trim() ?? '',
        country: (map['c'] as String?)?.trim() ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

/// Dati di un vino letti da un QR (vedi [WineQrCodec]).
class WineQrData {
  final String name;
  final String producer;
  final int? vintage;
  final String type;
  final String grape;
  final String region;
  final String denomination;
  final String country;
  const WineQrData({
    required this.name,
    this.producer = '',
    this.vintage,
    this.type = '',
    this.grape = '',
    this.region = '',
    this.denomination = '',
    this.country = '',
  });
}

/// Inquadra un codice (QR o barcode) con la fotocamera e ritorna il testo
/// grezzo letto (null se l'utente annulla). La decodifica in [WineQrData]
/// e' a carico di chi chiama, cosi' puo' distinguere "non e' un QR vino" da
/// "annullato" e proporre il fallback alla foto.
class WineQrScannerScreen extends StatefulWidget {
  const WineQrScannerScreen({super.key});

  @override
  State<WineQrScannerScreen> createState() => _WineQrScannerScreenState();
}

class _WineQrScannerScreenState extends State<WineQrScannerScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inquadra il QR o codice del vino')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) return;
          for (final barcode in capture.barcodes) {
            final raw = barcode.rawValue;
            if (raw == null) continue;
            _handled = true;
            Navigator.pop(context, raw);
            return;
          }
        },
      ),
    );
  }
}

/// Mostra il QR con i dati del vino, con un pulsante per stamparlo (o
/// salvarlo/condividerlo come PDF): utile per attaccarlo a una bottiglia
/// che non ha gia' un codice leggibile.
Future<void> showWineQrPrintDialog(BuildContext context, Wine wine) {
  final data = WineQrCodec.encode(wine);
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(wine.label, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Stampa questa etichetta e incollala sulla bottiglia: la '
            'prossima volta basta inquadrarla per riconoscere il vino.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          // Dimensione fissa: AlertDialog misura il contenuto con le
          // dimensioni intrinseche, che QrImageView non supporta da solo.
          SizedBox.square(
            dimension: 220,
            child: QrImageView(
              data: data,
              size: 220,
              version: QrVersions.auto,
              backgroundColor: Colors.white,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Chiudi'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.print),
          label: const Text('Stampa'),
          onPressed: () => _printWineQr(wine, data),
        ),
      ],
    ),
  );
}

Future<void> _printWineQr(Wine wine, String qrData) async {
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a6,
      build: (context) => pw.Center(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: qrData,
              width: 200,
              height: 200,
            ),
            pw.SizedBox(height: 12),
            pw.Text(wine.label, textAlign: pw.TextAlign.center),
          ],
        ),
      ),
    ),
  );
  await Printing.layoutPdf(onLayout: (_) => doc.save());
}
