import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../sync/cloud_sync_service.dart';

/// Dialoghi dei flussi email dell'autenticazione cloud (Fase 2).
///
/// Tutti i flussi funzionano col LINK contenuto nell'email (template di
/// default di Supabase): aprendolo, il deep link riporta nell'app già
/// autenticati. Questi dialoghi si limitano a invitare l'utente a
/// controllare la posta — nessun codice da ricopiare.

/// "Password dimenticata": chiede l'email e spedisce il link di recupero.
/// Quando l'utente apre il link, l'app si riapre già autenticata e la UI
/// (che ascolta [CloudSyncService.authChanges]) propone la nuova password.
Future<void> showPasswordResetDialog(BuildContext context,
    {String initialEmail = ''}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PasswordResetDialog(initialEmail: initialEmail),
  );
}

/// Invito a confermare l'email: spiega di aprire il link ricevuto via email.
/// Il bottone "Ho confermato" riprova l'accesso con [email] e [password].
/// Ritorna `true` se l'accesso è riuscito (email confermata).
Future<bool?> showCheckEmailDialog(BuildContext context,
    {required String email, required String password}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CheckEmailDialog(email: email, password: password),
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
// Password dimenticata (email → link → si torna nell'app)
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
  StreamSubscription<AuthState>? _authSub;

  bool _sent = false;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    // Se l'utente apre il link mentre il dialogo è ancora aperto, il deep
    // link lo riporta nell'app già autenticato: il dialogo si chiude da solo
    // (poi la UI sotto propone la nuova password).
    _authSub = _cloud.authChanges.listen((state) {
      if (state.session != null && mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Inserisci un\'email valida.');
      return;
    }
    await _run(() async {
      await _cloud.sendPasswordResetEmail(email);
      if (_sent) _info = 'Email inviata di nuovo. Controlla anche lo spam.';
      _sent = true;
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
      title: Text(_sent ? 'Controlla la tua email' : 'Recupera password'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_sent) ...[
              const Text(
                  'Ti mandiamo un\'email con un link per scegliere una '
                  'nuova password.'),
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
              Center(
                child: Icon(Icons.mark_email_unread_outlined,
                    size: 56, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 16),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Ti abbiamo mandato un\'email a '),
                    TextSpan(
                        text: _email.text.trim(),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const TextSpan(
                        text: '.\n\nApri il link che contiene: tornerai '
                            'nell\'app e potrai scegliere subito la nuova '
                            'password.'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text('Se non la vedi, controlla anche lo spam.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              TextButton(
                onPressed: _busy ? null : _send,
                child: const Text('Non è arrivata? Invia di nuovo l\'email'),
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
        if (!_sent) ...[
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: _busy ? null : _send,
            child: const Text('Invia email'),
          ),
        ] else
          FilledButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('OK'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Conferma registrazione (link ricevuto via email)
// ---------------------------------------------------------------------------

class _CheckEmailDialog extends StatefulWidget {
  final String email;
  final String password;
  const _CheckEmailDialog({required this.email, required this.password});

  @override
  State<_CheckEmailDialog> createState() => _CheckEmailDialogState();
}

class _CheckEmailDialogState extends State<_CheckEmailDialog> {
  final _cloud = CloudSyncService.instance;
  StreamSubscription<AuthState>? _authSub;

  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    // Aprendo il link di conferma, il deep link riporta nell'app già
    // autenticati: il dialogo si chiude da solo con esito positivo.
    _authSub = _cloud.authChanges.listen((state) {
      if (state.session != null && mounted) Navigator.pop(context, true);
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  /// "Ho confermato": riprova il login. Se l'email non risulta ancora
  /// confermata lo spieghiamo senza chiudere il dialogo.
  Future<void> _tryLogin() async {
    await _run(() async {
      try {
        await _cloud.signIn(widget.email, widget.password);
        if (mounted) Navigator.pop(context, true);
      } on AuthException catch (e) {
        final notConfirmed = e.code == 'email_not_confirmed' ||
            e.message.toLowerCase().contains('not confirmed');
        if (!notConfirmed) rethrow;
        _error = 'L\'email non risulta ancora confermata. Apri il link '
            'nell\'email che ti abbiamo mandato, poi riprova.';
      }
    });
  }

  Future<void> _resend() async {
    await _run(() async {
      await _cloud.resendSignupEmail(widget.email);
      _info = 'Email inviata di nuovo. Controlla anche lo spam.';
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
      title: const Text('Controlla la tua email'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Icon(Icons.mark_email_unread_outlined,
                  size: 56, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Ti abbiamo mandato un\'email a '),
                  TextSpan(
                      text: widget.email,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(
                      text: '.\n\nApri il link di conferma che contiene: '
                          'tornerai nell\'app già connesso. Se lo apri da un '
                          'altro dispositivo, torna qui e tocca '
                          '"Ho confermato".'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('Se non la vedi, controlla anche lo spam.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            TextButton(
              onPressed: _busy ? null : _resend,
              child: const Text('Non è arrivata? Invia di nuovo l\'email'),
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
          onPressed: _busy ? null : _tryLogin,
          child: const Text('Ho confermato'),
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
