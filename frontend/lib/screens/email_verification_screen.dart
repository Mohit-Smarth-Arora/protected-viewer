import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/session.dart';

/// Shown right after registration, before the account can do anything
/// else. The 6-digit code is emailed via SendGrid in production, or logged
/// to the backend's console in local dev when SENDGRID_API_KEY isn't set
/// (see backend/src/lib/email.js).
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final _codeController = TextEditingController();
  bool _isSubmitting = false;
  bool _isResending = false;
  String? _resendMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final session = context.read<Session>();
    setState(() => _isSubmitting = true);
    await session.verifyEmail(_codeController.text.trim());
    if (mounted) setState(() => _isSubmitting = false);
  }

  Future<void> _resend() async {
    final session = context.read<Session>();
    setState(() {
      _isResending = true;
      _resendMessage = null;
    });
    final res = await session.resendVerification();
    if (!mounted) return;
    setState(() {
      _isResending = false;
      _resendMessage = res.ok ? 'A new code has been sent.' : (res.error ?? 'Could not resend code');
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify your email'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () => session.signOut()),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.mark_email_read_outlined, size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  'Enter the code we sent to ${session.userEmail ?? "your email"}',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _codeController,
                  decoration: const InputDecoration(labelText: '6-digit code'),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, letterSpacing: 8),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
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
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Verify'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _isResending ? null : _resend,
                  child: Text(_isResending ? 'Sending...' : 'Resend code'),
                ),
                if (_resendMessage != null)
                  Text(
                    _resendMessage!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
