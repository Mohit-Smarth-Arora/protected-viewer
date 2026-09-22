import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/session.dart';
import '../widgets/auth_scaffold.dart';

/// Click-through no-redistribution agreement, shown once per account before
/// any asset route becomes reachable (enforced server-side by
/// requireAgreement middleware — this screen is just the UI for it).
class AgreementScreen extends StatefulWidget {
  const AgreementScreen({super.key});

  @override
  State<AgreementScreen> createState() => _AgreementScreenState();
}

class _AgreementScreenState extends State<AgreementScreen> {
  bool _checked = false;
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final scheme = Theme.of(context).colorScheme;

    return AuthScaffold(
      maxWidth: 560,
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Before you continue')),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Viewing terms',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'The content in this app (images, code, video) is shared with '
              'you for viewing purposes only. By continuing you agree that '
              'you will not:\n\n'
              '  • Copy, redistribute, or publish this content\n'
              '  • Share your account access with anyone else\n'
              '  • Attempt to circumvent the viewing protections in this app\n\n'
              'Every view of every asset is logged against your account, '
              'including a per-view watermark carrying your email and the '
              'exact time of access.',
            ),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _checked,
            onChanged: (v) => setState(() => _checked = v ?? false),
            title: const Text('I have read and agree to these terms'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 12),
          if (session.lastError != null) ...[
            Text(
              session.lastError!,
              style: TextStyle(color: scheme.error),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: (_checked && !_isSubmitting)
                ? () async {
                    setState(() => _isSubmitting = true);
                    await session.acceptAgreement();
                    if (mounted) setState(() => _isSubmitting = false);
                  }
                : null,
            child: _isSubmitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Continue'),
          ),
          TextButton(
            onPressed: _isSubmitting ? null : () => session.signOut(),
            child: const Text('Sign out instead'),
          ),
        ],
      ),
    );
  }
}
