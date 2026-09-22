import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/session.dart';
import '../widgets/auth_scaffold.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _referralController = TextEditingController();

  bool _isRegisterMode = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _referralController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final session = context.read<Session>();
    setState(() => _isSubmitting = true);
    if (_isRegisterMode) {
      await session.register(
        _emailController.text.trim(),
        _passwordController.text,
        _nameController.text.trim(),
        referralCode: _referralController.text.trim().isEmpty ? null : _referralController.text.trim(),
      );
    } else {
      await session.login(_emailController.text.trim(), _passwordController.text);
    }
    if (mounted) setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();

    return AuthScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: BrandMark()),
          const SizedBox(height: 16),
          Text(
            'Protected Viewer',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'View-only access — all content is watermarked per session.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          if (_isRegisterMode) ...[
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(labelText: 'Email'),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            decoration: const InputDecoration(labelText: 'Password'),
            obscureText: true,
            onSubmitted: (_) => _submit(),
          ),
          if (_isRegisterMode) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _referralController,
              decoration: const InputDecoration(
                labelText: 'Referral code (optional)',
                helperText: 'Skips admin approval if valid. Leave blank to request approval instead.',
              ),
              textCapitalization: TextCapitalization.characters,
            ),
          ],
          const SizedBox(height: 20),
          if (session.lastError != null) ...[
            Text(
              session.lastError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isRegisterMode ? 'Create account' : 'Sign in'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _isSubmitting
                ? null
                : () => setState(() => _isRegisterMode = !_isRegisterMode),
            child: Text(
              _isRegisterMode
                  ? 'Already have an account? Sign in'
                  : "Don't have an account? Register",
            ),
          ),
        ],
      ),
    );
  }
}
