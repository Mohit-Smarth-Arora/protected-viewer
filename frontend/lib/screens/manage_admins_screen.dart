import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/state_views.dart';

class AdminSummary {
  AdminSummary.fromJson(Map<String, dynamic> json)
      : id = json['id'] as int,
        email = json['email'] as String,
        displayName = json['display_name'] as String,
        role = json['role'] as String,
        hasMasterAccess = json['has_master_access'] == 1 || json['has_master_access'] == true;

  final int id;
  final String email;
  final String displayName;
  final String role; // 'admin' | 'owner'
  final bool hasMasterAccess;
}

/// Owner/master-access-only: list current admins + the owner, and toggle
/// master access on individual admins. The owner's own row is shown
/// read-only — backend rejects any attempt to modify it.
class ManageAdminsScreen extends StatefulWidget {
  const ManageAdminsScreen({super.key});

  @override
  State<ManageAdminsScreen> createState() => _ManageAdminsScreenState();
}

class _ManageAdminsScreenState extends State<ManageAdminsScreen> {
  List<AdminSummary>? _admins;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final res = await api.listAdmins();
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _error = res.error ?? 'Failed to load admins');
      return;
    }
    final list = (res.body['admins'] as List)
        .map((a) => AdminSummary.fromJson(a as Map<String, dynamic>))
        .toList();
    setState(() {
      _admins = list;
      _error = null;
    });
  }

  Future<void> _toggleMasterAccess(AdminSummary admin, bool grant) async {
    final api = context.read<ApiClient>();
    final res = await api.setAdminMasterAccess(admin.id, grant: grant);
    if (!mounted) return;
    if (res.ok) {
      _load();
      // If this is our own account, refresh session role info too.
      final session = context.read<Session>();
      if (session.userId == admin.id) session.refreshUserInfo();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error ?? 'Could not update access')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage admins')),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    if (_admins == null) {
      return const LoadingState();
    }
    if (_admins!.isEmpty) {
      return const EmptyState(icon: Icons.admin_panel_settings_outlined, message: 'No admins yet.');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: _admins!.length,
      itemBuilder: (context, i) {
        final admin = _admins![i];
        final isOwner = admin.role == 'owner';
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: TonalIcon(isOwner ? Icons.workspace_premium : Icons.admin_panel_settings_outlined),
            title: Text(admin.displayName),
            subtitle: Text('${admin.email} • ${isOwner ? "Owner" : "Admin"}'),
            trailing: isOwner
                ? const Chip(label: Text('Always full access'))
                : Switch(
                    value: admin.hasMasterAccess,
                    onChanged: (value) => _toggleMasterAccess(admin, value),
                  ),
          ),
        );
      },
    );
  }
}
