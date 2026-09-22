import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/session.dart';
import '../screens/admin_request_screen.dart';
import '../screens/admin_review_screen.dart';
import '../screens/manage_admins_screen.dart';
import '../screens/manage_assets_screen.dart';
import '../screens/user_activity_screen.dart';
import '../screens/chat_screens.dart';
import '../screens/referral_codes_screen.dart';
import '../screens/signup_requests_screen.dart';

/// App-wide navigation drawer, grouped by section. Replaces the old
/// PopupMenuButton overflow menu — that pattern stopped scaling once the
/// admin surface grew past ~5 destinations. Role gating here is purely for
/// UI convenience; every destination re-enforces its own access
/// server-side regardless of what this drawer shows.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final scheme = Theme.of(context).colorScheme;

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _DrawerHeader(session: session),
            const SizedBox(height: 4),
            if (session.isAdmin) ...[
              _SectionLabel('Library'),
              _DrawerTile(
                icon: Icons.folder_shared_outlined,
                label: 'Manage assets',
                onTap: () => _push(context, const ManageAssetsScreen()),
              ),
              _SectionLabel('People'),
              _DrawerTile(
                icon: Icons.mark_chat_unread_outlined,
                label: 'Chat requests',
                onTap: () => _push(context, const ChatRequestsScreen()),
              ),
              _DrawerTile(
                icon: Icons.chat_outlined,
                label: 'Messages',
                onTap: () => _push(context, const ChatThreadsScreen()),
              ),
              _DrawerTile(
                icon: Icons.people_outline,
                label: 'Users & activity',
                onTap: () => _push(context, const UserActivityScreen()),
              ),
              _DrawerTile(
                icon: Icons.how_to_reg_outlined,
                label: 'Signup requests',
                onTap: () => _push(context, const SignupRequestsScreen()),
              ),
            ],
            if (session.effectiveMasterAccess) ...[
              _SectionLabel('Owner controls'),
              _DrawerTile(
                icon: Icons.fact_check_outlined,
                label: 'Review admin requests',
                onTap: () => _push(context, const AdminReviewScreen()),
              ),
              _DrawerTile(
                icon: Icons.admin_panel_settings_outlined,
                label: 'Manage admins',
                onTap: () => _push(context, const ManageAdminsScreen()),
              ),
              _DrawerTile(
                icon: Icons.qr_code,
                label: 'Referral codes',
                onTap: () => _push(context, const ReferralCodesScreen()),
              ),
            ],
            if (!session.isAdmin) ...[
              _SectionLabel('Get help'),
              _DrawerTile(
                icon: Icons.chat_bubble_outline,
                label: 'Message an admin',
                onTap: () => _push(context, const RequestChatScreen()),
              ),
              _DrawerTile(
                icon: Icons.upgrade_outlined,
                label: 'Request admin access',
                onTap: () => _push(context, const AdminRequestScreen()),
              ),
            ],
            const Divider(height: 24),
            _DrawerTile(
              icon: Icons.logout,
              label: 'Sign out',
              color: scheme.error,
              onTap: () {
                Navigator.of(context).pop();
                session.signOut();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).pop(); // close the drawer first
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roleLabel = switch (session.role) {
      'owner' => 'Owner',
      'admin' => session.hasMasterAccess ? 'Admin • master access' : 'Admin',
      _ => 'Viewer',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(color: scheme.surfaceContainerLow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: scheme.primaryContainer,
            child: Icon(Icons.shield_outlined, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 12),
          Text(
            session.userDisplayName ?? 'Protected Viewer',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            session.userEmail ?? '',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Chip(
            label: Text(roleLabel, style: const TextStyle(fontSize: 11)),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label, style: color != null ? TextStyle(color: color) : null),
        onTap: onTap,
        dense: true,
      ),
    );
  }
}
