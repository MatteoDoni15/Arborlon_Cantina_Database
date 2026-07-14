import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/app_settings.dart';
import '../../sync/cloud_sync_service.dart';
import 'invite_qr.dart';

/// Sezione "Cloud (Premium)" delle impostazioni.
///
/// È un PLUS: non tocca il P2P. Qui l'utente attiva il premium (per ora un
/// flag), sceglie la modalità di sync, accede al cloud, crea/entra in un
/// ristorante (multi-tenant) e lancia una sincronizzazione a distanza.
class CloudSettingsCard extends StatefulWidget {
  const CloudSettingsCard({super.key});

  @override
  State<CloudSettingsCard> createState() => _CloudSettingsCardState();
}

class _CloudSettingsCardState extends State<CloudSettingsCard> {
  final _settings = AppSettings.instance;
  final _cloud = CloudSyncService.instance;

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _newRestaurant = TextEditingController();
  final _joinCode = TextEditingController();
  bool _busy = false;
  StreamSubscription<dynamic>? _authSub;

  @override
  void initState() {
    super.initState();
    // Il login Google si conclude FUORI dall'app (browser + deep link):
    // ridisegna la card quando lo stato di autenticazione cambia.
    if (_cloud.isAvailable) {
      _authSub = _cloud.authChanges.listen((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _email.dispose();
    _password.dispose();
    _newRestaurant.dispose();
    _joinCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_outlined),
                const SizedBox(width: 8),
                Text('Cloud (Premium)',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Sincronizzazione a distanza tra più dispositivi, anche fuori dal '
              'ristorante. La sync P2P sul WiFi resta sempre disponibile e '
              'gratuita: il cloud è un extra.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (!_cloud.isAvailable) _notConfigured() else _configured(),
          ],
        );
      },
    );
  }

  // Cloud non configurato (chiavi Supabase assenti).
  Widget _notConfigured() {
    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cloud non ancora attivo su questa build',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Per abilitarlo servono le chiavi del progetto Supabase '
              '(vedi docs/CLOUD-SETUP.md). Nel frattempo l\'app funziona '
              'normalmente in locale e in P2P.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _configured() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sblocco premium (per ora flag manuale).
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Abbonamento premium'),
          subtitle: const Text(
              'Sblocca la modalità Cloud (in futuro: acquisto in-app).'),
          value: _settings.premium,
          onChanged: _busy ? null : (v) => _settings.setPremium(v),
        ),
        if (_settings.premium) ...[
          const SizedBox(height: 8),
          const Text('Modalità di sincronizzazione',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<SyncMode>(
            segments: const [
              ButtonSegment(
                value: SyncMode.p2p,
                label: Text('Locale P2P'),
                icon: Icon(Icons.wifi),
              ),
              ButtonSegment(
                value: SyncMode.cloud,
                label: Text('Cloud'),
                icon: Icon(Icons.cloud),
              ),
            ],
            selected: {_settings.mode},
            onSelectionChanged:
                _busy ? null : (s) => _settings.setMode(s.first),
          ),
          const SizedBox(height: 16),
          if (_settings.mode == SyncMode.cloud) _cloudControls(),
        ],
      ],
    );
  }

  Widget _cloudControls() {
    // 1) Non loggato → form email/password.
    if (!_cloud.isSignedIn) return _loginForm();

    // 2) Loggato ma senza ristorante → crea o entra.
    if (!_settings.hasRestaurant) return _restaurantChooser();

    // 3) Loggato + ristorante scelto → sincronizza.
    return _syncPanel();
  }

  Widget _loginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Accedi al cloud',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.email),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            prefixIcon: Icon(Icons.lock),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : () => _auth(signUp: false),
                child: const Text('Accedi'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => _auth(signUp: true),
                child: const Text('Registrati'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('oppure',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          onPressed: _busy ? null : _googleSignIn,
          icon: const Icon(Icons.g_mobiledata, size: 30),
          label: const Text('Continua con Google'),
        ),
      ],
    );
  }

  Widget _restaurantChooser() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _accountRow(),
        const Divider(height: 28),

        // Crea un nuovo ristorante.
        const Text('Crea il tuo ristorante',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _newRestaurant,
          decoration: const InputDecoration(
            labelText: 'Nome ristorante',
            prefixIcon: Icon(Icons.store),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _createRestaurant,
          icon: const Icon(Icons.add_business),
          label: const Text('Crea ristorante'),
        ),

        const Divider(height: 28),

        // Entra in un ristorante: QR di un collega oppure codice scritto.
        const Text('Oppure entra in un ristorante esistente',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _scanInvite,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Inquadra il QR invito di un collega'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _joinCode,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Codice invito',
            helperText: 'Te lo dà un collega che ha già creato il ristorante.',
            prefixIcon: Icon(Icons.vpn_key),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _joinRestaurant,
          icon: const Icon(Icons.login),
          label: const Text('Entra con codice invito'),
        ),
      ],
    );
  }

  Widget _syncPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _accountRow(),
        const SizedBox(height: 12),

        // Ristorante attivo + codice invito da condividere.
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.store),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_settings.restaurantName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    _planBadge(),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Codice invito per i colleghi:'),
                const SizedBox(height: 4),
                Row(
                  children: [
                    SelectableText(
                      _settings.inviteCode,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Copia',
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: _settings.inviteCode));
                        _snack('Codice copiato');
                      },
                    ),
                    IconButton(
                      tooltip: 'Mostra QR invito',
                      icon: const Icon(Icons.qr_code_2),
                      onPressed: () => showInviteQrDialog(
                        context,
                        restaurantName: _settings.restaurantName,
                        inviteCode: _settings.inviteCode,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        if (!_settings.restaurantHasCloud)
          _cloudLocked()
        else
          FilledButton.icon(
            onPressed: _busy ? null : _syncNow,
            icon: const Icon(Icons.cloud_sync),
            label: const Text('Sincronizza col cloud ora'),
          ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: _busy ? null : _leaveRestaurant,
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Cambia ristorante'),
        ),
      ],
    );
  }

  // Piano gratuito: la sync cloud è bloccata dal server finché il gestore non
  // attiva il piano. Da qui parte la richiesta di attivazione; l'acquisto
  // in-app prenderà il posto della richiesta quando ci saranno i pagamenti.
  Widget _cloudLocked() {
    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lock_outline),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Cloud non attivo per questo ristorante',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'La sincronizzazione a distanza fa parte della versione Pro. '
              'Invia la richiesta di attivazione: appena approvata, il badge '
              'diventerà "Cloud" e potrai sincronizzare. (Acquisto in-app in '
              'arrivo.)',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _requestCloud,
              icon: const Icon(Icons.send),
              label: const Text('Richiedi attivazione Cloud'),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _checkPlan,
              icon: const Icon(Icons.refresh),
              label: const Text('Ho fatto richiesta: controlla se è attivo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planBadge() {
    final cloud = _settings.restaurantHasCloud;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cloud ? Colors.green.shade600 : Colors.grey.shade400,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        cloud ? 'Cloud' : 'Gratuito',
        style: const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _accountRow() {
    return Row(
      children: [
        const Icon(Icons.verified_user, color: Colors.green),
        const SizedBox(width: 8),
        Expanded(child: Text('Account: ${_cloud.currentEmail}')),
        TextButton(
          onPressed: _busy ? null : _signOut,
          child: const Text('Esci'),
        ),
      ],
    );
  }

  // -------------------------------------------------------------- azioni

  Future<void> _auth({required bool signUp}) async {
    await _run(() async {
      if (signUp) {
        await _cloud.signUp(_email.text, _password.text);
        _snack('Registrazione avviata: controlla la mail se richiesto.');
      } else {
        await _cloud.signIn(_email.text, _password.text);
        _snack('Accesso eseguito.');
      }
    });
  }

  Future<void> _googleSignIn() async {
    await _run(() async {
      await _cloud.signInWithGoogle();
      _snack('Completa l\'accesso nel browser: al termine tornerai nell\'app.');
    });
  }

  Future<void> _scanInvite() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const InviteScannerScreen()),
    );
    if (code == null || !mounted) return;
    await _run(() async {
      final info = await _cloud.joinRestaurant(code);
      _snack('Sei entrato in "${info.name}".');
    });
  }

  Future<void> _signOut() => _run(() => _cloud.signOut());

  Future<void> _createRestaurant() async {
    await _run(() async {
      final info = await _cloud.createRestaurant(_newRestaurant.text);
      _newRestaurant.clear();
      _snack('Ristorante creato. Codice invito: ${info.inviteCode}');
    });
  }

  Future<void> _joinRestaurant() async {
    await _run(() async {
      final info = await _cloud.joinRestaurant(_joinCode.text);
      _joinCode.clear();
      _snack('Sei entrato in "${info.name}".');
    });
  }

  Future<void> _leaveRestaurant() => _run(() => _settings.clearRestaurant());

  Future<void> _requestCloud() async {
    await _run(() async {
      final sent = await _cloud.requestCloud();
      _snack(sent
          ? 'Richiesta inviata! Riceverai l\'attivazione a breve.'
          : 'C\'è già una richiesta in attesa per questo ristorante.');
    });
  }

  Future<void> _checkPlan() async {
    await _run(() async {
      final plan = await _cloud.refreshPlan();
      _snack(plan == 'cloud'
          ? 'Cloud attivo! Ora puoi sincronizzare. 🎉'
          : 'Non ancora attivo: la richiesta è in lavorazione.');
    });
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Sincronizzazione cloud...')),
          ],
        ),
      ),
    );
    try {
      final stats = await _cloud.syncNow();
      if (!mounted) return;
      Navigator.pop(context);
      _dialog('Cloud sincronizzato ✅', stats.summary);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _dialog('Sincronizzazione cloud fallita', '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Esegue un'azione mostrando lo stato "busy" e gli errori come snackbar.
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _snack('Errore: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _dialog(String title, String body) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK')),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
