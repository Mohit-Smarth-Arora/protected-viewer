import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/session.dart';
import '../widgets/auth_scaffold.dart';

/// Shown to a viewer whose email is verified but who registered without a
/// valid referral code — their account is waiting for any admin to
/// approve it (backend/src/routes/admin.js signup-requests). No action for
/// the viewer to take here beyond waiting; refresh checks current status.
class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();

    return AuthScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Pending approval'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () => session.signOut()),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BrandMark(icon: Icons.hourglass_top),
          const SizedBox(height: 16),
          Text(
            'Waiting for approval',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text(
            'Your email is verified. An admin needs to approve your account before you can view '
            'shared content. If you have a referral code, sign out and register again with it to '
            'skip this step.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => session.refreshUserInfo(),
            icon: const Icon(Icons.refresh),
            label: const Text('Check again'),
          ),
        ],
      ),
    );
  }
}
