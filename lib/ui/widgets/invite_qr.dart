import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Codifica/decodifica del QR di invito a un ristorante cloud.
///
/// Formato volutamente diverso dal QR della sync P2P (che è un JSON con
/// ip/porta): un prefisso testuale + il codice invito, così i due scanner
/// non si confondono a vicenda.
class InviteQr {
  static const _prefix = 'CANTINA-INVITE:';

  static String encode(String inviteCode) =>
      '$_prefix${inviteCode.trim().toUpperCase()}';

  /// Ritorna il codice invito se [raw] è un QR di invito, altrimenti null.
  /// Accetta anche il codice scritto da solo (6 caratteri), per tolleranza.
  static String? tryParse(String raw) {
    final s = raw.trim().toUpperCase();
    if (s.startsWith(_prefix)) {
      final code = s.substring(_prefix.length).trim();
      return code.isEmpty ? null : code;
    }
    if (RegExp(r'^[A-Z0-9]{6}$').hasMatch(s)) return s;
    return null;
  }
}

/// Mostra il QR del codice invito da far inquadrare a un collega.
Future<void> showInviteQrDialog(
  BuildContext context, {
  required String restaurantName,
  required String inviteCode,
}) {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(restaurantName),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Fai inquadrare questo QR al collega: entrerà subito nel tuo '
            'ristorante.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          QrImageView(
            data: InviteQr.encode(inviteCode),
            size: 220,
            version: QrVersions.auto,
            backgroundColor: Colors.white,
          ),
          const SizedBox(height: 12),
          SelectableText(
            inviteCode,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy),
          label: const Text('Copia codice'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: inviteCode));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Codice copiato')),
            );
          },
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Scanner del QR invito. Ritorna il codice letto (null se annullato).
class InviteScannerScreen extends StatefulWidget {
  const InviteScannerScreen({super.key});

  @override
  State<InviteScannerScreen> createState() => _InviteScannerScreenState();
}

class _InviteScannerScreenState extends State<InviteScannerScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inquadra il QR invito')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) return;
          for (final barcode in capture.barcodes) {
            final raw = barcode.rawValue;
            if (raw == null) continue;
            final code = InviteQr.tryParse(raw);
            if (code != null) {
              _handled = true;
              Navigator.pop(context, code);
              return;
            }
          }
        },
      ),
    );
  }
}
