import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/session.dart';
import 'theme.dart';
import 'screens/login_screen.dart';
import 'screens/agreement_screen.dart';
import 'screens/asset_list_screen.dart';
import 'screens/email_verification_screen.dart';
import 'screens/pending_approval_screen.dart';

class ProtectedViewerApp extends StatelessWidget {
  const ProtectedViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Protected Viewer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const _RootRouter(),
    );
  }
}

/// Routes to the right screen based on session status. Deliberately simple
/// (no named routes / go_router yet) — revisit once the screen count grows
/// past what a switch can read cleanly.
class _RootRouter extends StatelessWidget {
  const _RootRouter();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();

    return switch (session.status) {
      AuthStatus.unknown || AuthStatus.signedOut => const LoginScreen(),
      AuthStatus.needsEmailVerification => const EmailVerificationScreen(),
      AuthStatus.pendingApproval => const PendingApprovalScreen(),
      AuthStatus.signedInNeedsAgreement => const AgreementScreen(),
      AuthStatus.signedIn => const AssetListScreen(),
    };
  }
}
