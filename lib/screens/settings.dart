import 'package:flutter/material.dart';

import '../format.dart';
import '../store.dart';
import '../sync.dart';
import 'calendars.dart';
import 'common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Instellingen')),
      body: ListenableBuilder(
        listenable: Listenable.merge([store, sync]),
        builder: (context, _) {
          final u = sync.user;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: Icon(u == null ? Icons.cloud_off : Icons.cloud_done_outlined,
                      color: u == null ? muted : Theme.of(context).colorScheme.primary),
                  title: const Text('Account en synchroniseren'),
                  subtitle: Text(u == null
                      ? 'Niet ingelogd: gegevens staan alleen op dit apparaat'
                      : u.email ?? 'Ingelogd'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AccountScreen())),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.event_available_outlined),
                  title: const Text('Rentman-agenda\'s'),
                  subtitle: Text('${store.calendars.length} gekoppeld'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CalendarsScreen())),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _email = TextEditingController();
  final _pw = TextEditingController();
  String? _msg;
  bool _busy = false;

  Future<void> _go(bool signUp) async {
    final e = _email.text.trim(), p = _pw.text;
    if (!e.contains('@')) {
      setState(() => _msg = 'Vul je e-mailadres in.');
      return;
    }
    if (p.length < 6) {
      setState(() => _msg = 'Het wachtwoord moet minstens 6 tekens hebben.');
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    final r = signUp ? await sync.signUp(e, p) : await sync.signIn(e, p);
    if (mounted) {
      setState(() {
        _busy = false;
        _msg = r;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListenableBuilder(
        listenable: Listenable.merge([store, sync]),
        builder: (context, _) {
          final u = sync.user;
          if (u != null) {
            final last = store.lastSyncTime;
            final pending = store.dirty.length;
            return ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Ingelogd als', style: TextStyle(color: muted)),
                        Text(u.email ?? '',
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        Text(last == null
                            ? 'Nog niet gesynchroniseerd'
                            : 'Laatst gesynchroniseerd: ${dateShort(last)} ${hm(last)}'),
                        if (pending > 0)
                          Text('$pending wijziging(en) wachten op verzenden',
                              style: const TextStyle(color: muted)),
                        if (sync.lastError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(sync.lastError!,
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.error)),
                          ),
                      ]),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: sync.busy ? null : sync.run,
                  icon: sync.busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync),
                  label: const Text('Nu synchroniseren'),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                  onPressed: sync.signOut, child: const Text('Uitloggen')),
              const SizedBox(height: 16),
              const Text(
                'Agenda\'s, eigen klussen, notities, foto\'s en uren worden gedeeld '
                'tussen je telefoon en de webversie. Zonder bereik werkt alles '
                'gewoon door; wijzigingen gaan mee zodra je weer online bent.',
                style: TextStyle(color: muted),
              ),
            ]);
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Text(
              'Log in om je gegevens te delen tussen je telefoon en de webversie, '
              'en om Rentman-agenda\'s in de browser te kunnen zien.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'E-mailadres'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pw,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Wachtwoord'),
              onSubmitted: (_) => _go(false),
            ),
            if (_msg != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_msg!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : () => _go(false),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Inloggen'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
                onPressed: _busy ? null : () => _go(true),
                child: const Text('Nog geen account? Account aanmaken')),
          ]);
        },
      ),
    );
  }
}
