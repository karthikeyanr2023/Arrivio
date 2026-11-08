import 'package:flutter/material.dart';

import 'api.dart';
import 'home.dart';
import 'registration.dart';
import 'shared_destination.dart';

void main() => runApp(const ArrivioApp());

class ArrivioApp extends StatefulWidget {
  const ArrivioApp({super.key});

  @override
  State<ArrivioApp> createState() => _ArrivioAppState();
}

class _ArrivioAppState extends State<ArrivioApp> {
  final shared = SharedDestination();

  @override
  void initState() {
    super.initState();
    shared.start();
  }

  @override
  void dispose() {
    shared.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Arrivio',
    theme: ThemeData(
      colorSchemeSeed: const Color(0xff1b6bd6),
      useMaterial3: true,
    ),
    home: LoginPage(shared: shared),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.shared});
  final SharedDestination shared;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final username = TextEditingController();
  final api = ArrivioApi();
  String? error;
  bool loading = false;

  @override
  void dispose() {
    username.dispose();
    super.dispose();
  }

  Future<void> login() async {
    final value = username.text.trim();
    if (value.isEmpty) {
      setState(() => error = 'Please enter a user name.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      List<Map<String, dynamic>> users = [];
      List<Map<String, dynamic>> merchants = [];
      Object? userError;
      Object? merchantError;
      try {
        users = await api.list(ArrivioApi.users);
      } catch (e) {
        userError = e;
      }
      try {
        merchants = await api.list(ArrivioApi.merchants);
      } catch (e) {
        merchantError = e;
      }
      bool matches(Map<String, dynamic> item) => [
        'email',
        'fullName',
      ].any((key) => '${item[key] ?? ''}'.toLowerCase() == value.toLowerCase());
      final user = users.where(matches).firstOrNull;
      final merchant = merchants.where(matches).firstOrNull;
      if (!mounted) return;
      if (user == null && merchant == null) {
        setState(
          () => error = userError != null || merchantError != null
              ? 'Could not check all accounts. Please try again. ${userError ?? merchantError}'
              : 'No user or merchant found with that user name.',
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HomePage(
            username: value,
            profile: user ?? merchant!,
            isMerchant: user == null,
            shared: widget.shared,
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = 'Unable to check the user name: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Arrivio',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 8),
              const Text('Travel smarter', textAlign: TextAlign.center),
              const SizedBox(height: 32),
              const Text(
                'Prototype: login checks your user name only. Passwords are not verified.',
              ),
              ListenableBuilder(
                listenable: widget.shared,
                builder: (context, _) {
                  final shared = widget.shared;
                  if (shared.error != null) return Text(shared.error!);
                  if (shared.destination != null) {
                    return const Text(
                      'Destination received. Log in as a user to use it.',
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: username,
                decoration: const InputDecoration(
                  labelText: 'User Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: loading ? null : login,
                child: Text(loading ? 'Checking...' : 'Login'),
              ),
              OutlinedButton(
                onPressed: loading
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const RegistrationPage(),
                        ),
                      ),
                child: const Text('User Profile'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
