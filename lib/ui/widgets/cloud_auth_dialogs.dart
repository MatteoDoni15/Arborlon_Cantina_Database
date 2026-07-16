import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../sync/cloud_sync_service.dart';

/// Dialoghi dei flussi email dell'autenticazione cloud (Fase 2).
///
/// Su mobile evitiamo i link nelle email (richiederebbero i deep link):
/// tutti i flussi usano un CODICE a 6 cifre che l'utente ricopia nell'app.
/// Perché il codice compaia nelle email, i template su Supabase devono
/// contenere `{{ .Token }}` — vedi docs/CLOUD-SETUP.md.

/// "Password dimenticata": chiede l'email, spedisce il codice, poi chiede
/// codice + nuova password. Ritorna `true` se la password è stata cambiata
/// (a quel punto l'utente risulta anche loggato).
Future<bool?> showPasswordResetDialog(BuildContext context,
    {String initialEmail = ''}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PasswordResetDialog(initialEmail: initialEmail),
  );
}

/// Conferma della registrazione: chiede il codice ricevuto via email.
/// Ritorna `true` se l'email è stata confermata (utente loggato).
Future<bool?> showConfirmSignupDialog(BuildContext context,
    {required String email}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ConfirmSignupDialog(email: email),
  );
}

/// Cambio password per l'utente già loggato. Ritorna `true` se salvata.
Future<bool?> showChangePasswordDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ChangePasswordDialog(),
  );
}

/// Messaggio leggibile per gli errori di autenticazione.
String _errorText(Object e) => e is AuthException ? e.message : '$e';

// ---------------------------------------------------------------------------
// Password dimenticata (2 passi: email → codice + nuova password)
// ---------------------------------------------------------------------------

class _PasswordResetDialog extends StatefulWidget {
  final String initialEmail;
  const _PasswordResetDialog({required this.initialEmail});

  @override
  State<_PasswordResetDialog> createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<_PasswordResetDialog> {
  final _cloud = CloudSyncService.instance;
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();

  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Inserisci un\'email valida.');
      return;
    }
    await _run(() async {
      await _cloud.sendPasswordResetCode(email);
      _codeSent = true;
      _info = 'Codice inviato a $email. Controlla anche lo spam.';
    });
  }

  Future<void> _confirm() async {
    if (_code.text.trim().length < 6) {
      setState(() => _error = 'Inserisci il codice a 6 cifre ricevuto via email.');
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = 'La nuova password deve avere almeno 6 caratteri.');
      return;
    }
    if (_password.text != _password2.text) {
      setState(() => _error = 'Le due password non coincidono.');
      return;
    }
    await _run(() async {
      await _cloud.confirmPasswordReset(
        email: _email.text,
        code: _code.text,
        newPassword: _password.text,
      );
      if (mounted) Navigator.pop(context, true);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
    } catch (e) {
      _error = _errorText(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Recupera password'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_codeSent) ...[
              const Text(
                  'Ti mandiamo via email un codice a 6 cifre per scegliere '
                  'una nuova password.'),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
                ),
              ),
            ] else ...[
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Codice ricevuto via email',
                  prefixIcon: Icon(Icons.pin),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Nuova password',
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _password2,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Ripeti la nuova password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              TextButton(
                onPressed: _busy ? null : _sendCode,
                child: const Text('Non è arrivato? Invia un nuovo codice'),
              ),
            ],
            if (_info != null) ...[
              const SizedBox(height: 8),
              Text(_info!, style: TextStyle(color: Colors.green.shade700)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _busy ? null : (_codeSent ? _confirm : _sendCode),
          child: Text(_codeSent ? 'Cambia password' : 'Invia codice'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Conferma registrazione (codice ricevuto via email)
// ---------------------------------------------------------------------------

class _ConfirmSignupDialog extends StatefulWidget {
  final String email;
  const _ConfirmSignupDialog({required this.email});

  @override
  State<_ConfirmSignupDialog> createState() => _ConfirmSignupDialogState();
}

class _ConfirmSignupDialogState extends State<_ConfirmSignupDialog> {
  final _cloud = CloudSyncService.instance;
  final _code = TextEditingController();

  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_code.text.trim().length < 6) {
      setState(() => _error = 'Inserisci il codice a 6 cifre ricevuto via email.');
      return;
    }
    await _run(() async {
      await _cloud.confirmSignup(email: widget.email, code: _code.text);
      if (mounted) Navigator.pop(context, true);
    });
  }

  Future<void> _resend() async {
    await _run(() async {
      await _cloud.resendSignupCode(widget.email);
      _info = 'Nuovo codice inviato. Controlla anche lo spam.';
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
    } catch (e) {
      _error = _errorText(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Conferma la tua email'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Abbiamo mandato un codice a 6 cifre a ${widget.email}. '
                'Inseriscilo qui per attivare l\'account.'),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Codice di conferma',
                prefixIcon: Icon(Icons.pin),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : _resend,
              child: const Text('Non è arrivato? Invia un nuovo codice'),
            ),
            if (_info != null) ...[
              const SizedBox(height: 8),
              Text(_info!, style: TextStyle(color: Colors.green.shade700)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Più tardi'),
        ),
        FilledButton(
          onPressed: _busy ? null : _confirm,
          child: const Text('Conferma'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Cambio password (utente già loggato)
// ---------------------------------------------------------------------------

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _cloud = CloudSyncService.instance;
  final _password = TextEditingController();
  final _password2 = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text.length < 6) {
      setState(() => _error = 'La nuova password deve avere almeno 6 caratteri.');
      return;
    }
    if (_password.text != _password2.text) {
      setState(() => _error = 'Le due password non coincidono.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _cloud.changePassword(_password.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _error = _errorText(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambia password'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _password,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nuova password',
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _password2,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Ripeti la nuova password',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Salva'),
        ),
      ],
    );
  }
}
