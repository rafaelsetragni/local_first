import 'package:flutter/material.dart';
import '../services/repository_service.dart';

/// Simple sign-in form to capture the username.
class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  bool _isSigningIn = false;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  /// Handles sign-in by persisting the user and navigating to home.
  Future<void> _signIn(BuildContext context) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final errorColor = Theme.of(context).colorScheme.error;
    final scafold = ScaffoldMessenger.of(context);
    final username = _usernameController.text;

    setState(() => _isSigningIn = true);
    try {
      await RepositoryService().signIn(username: username);
    } catch (e) {
      scafold.showSnackBar(
        SnackBar(
          backgroundColor: errorColor,
          content: Text('No connection to the server. Error: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSigningIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'WebSocket Real-Time Counter',
                      style: TextTheme.of(context).headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Sign In',
                      style: TextTheme.of(context).labelLarge?.copyWith(
                            color: ColorScheme.of(context).primary,
                          ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                      ),
                      onFieldSubmitted: (_) => _signIn(context),
                      validator: (value) => (value == null || value.trim().isEmpty)
                          ? 'Please enter a username.'
                          : null,
                    ),
                    SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isSigningIn ? null : () => _signIn(context),
                      child: _isSigningIn
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign In'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
