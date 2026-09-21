import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import 'chat_screens.dart';

/// Admin-only (plain admin and up): three tabs — all accounts, sign-in
/// history, and who's active right now (heartbeat-based, see
/// state/session.dart and backend/src/routes/admin.js activity/online).
class UserActivityScreen extends StatelessWidget {
  const UserActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Users & activity'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Accounts'),
              Tab(text: 'Sign-in history'),
              Tab(text: 'Active now'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_AccountsTab(), _LoginHistoryTab(), _OnlineNowTab()],
        ),
      ),
    );
  }
}

class _AccountsTab extends StatefulWidget {
  const _AccountsTab();

  @override
  State<_AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends State<_AccountsTab> {
  List<Map<String, dynamic>>? _accounts;
  String? _error;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(() => setState(() => _query = _searchController.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredAccounts {
    if (_accounts == null) return [];
    if (_query.isEmpty) return _accounts!;
    return _accounts!
        .where((a) =>
            (a['display_name'] as String).toLowerCase().contains(_query) ||
            (a['email'] as String).toLowerCase().contains(_query))
        .toList();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final res = await api.listAccounts();
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _error = res.error ?? 'Failed to load accounts');
      return;
    }
    setState(() {
      _accounts = (res.body['accounts'] as List).cast<Map<String, dynamic>>();
      _error = null;
    });
  }

  Future<void> _messageViewer(BuildContext context, Map<String, dynamic> account) async {
    final messageController = TextEditingController();
    final body = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Message ${account['display_name']}'),
        content: TextField(
          controller: messageController,
          decoration: const InputDecoration(hintText: 'Type a message to start the conversation'),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(messageController.text.trim()),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (body == null || body.isEmpty || !context.mounted) return;

    final api = context.read<ApiClient>();
    final res = await api.startDirectMessage(account['id'] as int, body);
    if (!context.mounted) return;
    if (res.ok) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatThreadScreen(
            threadId: res.body['threadId'] as int,
            otherPartyName: account['display_name'] as String,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error ?? 'Could not send message')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!));
    if (_accounts == null) return const Center(child: CircularProgressIndicator());
    if (_accounts!.isEmpty) return const Center(child: Text('No accounts.'));

    final filtered = _filteredAccounts;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search by name or email',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: filtered.isEmpty
                ? ListView(children: const [SizedBox(height: 40), Center(child: Text('No matches.'))])
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final a = filtered[i];
                      final role = a['role'] as String;
                      return ListTile(
                        leading: Icon(switch (role) {
                          'owner' => Icons.workspace_premium,
                          'admin' => Icons.admin_panel_settings_outlined,
                          _ => Icons.person_outline,
                        }),
                        title: Text(a['display_name'] as String),
                        subtitle: Text('${a['email']} • joined ${a['created_at']}'),
                        trailing: role == 'viewer'
                            ? IconButton(
                                icon: const Icon(Icons.chat_bubble_outline),
                                tooltip: 'Message',
                                onPressed: () => _messageViewer(context, a),
                              )
                            : Chip(label: Text(role)),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _LoginHistoryTab extends StatefulWidget {
  const _LoginHistoryTab();

  @override
  State<_LoginHistoryTab> createState() => _LoginHistoryTabState();
}

class _LoginHistoryTabState extends State<_LoginHistoryTab> {
  List<Map<String, dynamic>>? _logins;
  String? _error;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(() => setState(() => _query = _searchController.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final res = await api.listLoginHistory();
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _error = res.error ?? 'Failed to load login history');
      return;
    }
    setState(() {
      _logins = (res.body['logins'] as List).cast<Map<String, dynamic>>();
      _error = null;
    });
  }

  List<Map<String, dynamic>> get _filteredLogins {
    if (_logins == null) return [];
    if (_query.isEmpty) return _logins!;
    return _logins!
        .where((l) =>
            (l['display_name'] as String).toLowerCase().contains(_query) ||
            (l['email'] as String).toLowerCase().contains(_query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!));
    if (_logins == null) return const Center(child: CircularProgressIndicator());
    if (_logins!.isEmpty) return const Center(child: Text('No sign-ins recorded yet.'));

    final filtered = _filteredLogins;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search by name or email',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: filtered.isEmpty
                ? ListView(children: const [SizedBox(height: 40), Center(child: Text('No matches.'))])
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final l = filtered[i];
                      return ListTile(
                        leading: const Icon(Icons.login),
                        title: Text(l['display_name'] as String),
                        subtitle: Text('${l['email']} • ${l['ip'] ?? 'unknown IP'}'),
                        trailing: Text(
                          (l['created_at'] as String).replaceFirst(' ', '\n'),
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _OnlineNowTab extends StatefulWidget {
  const _OnlineNowTab();

  @override
  State<_OnlineNowTab> createState() => _OnlineNowTabState();
}

class _OnlineNowTabState extends State<_OnlineNowTab> {
  List<Map<String, dynamic>>? _online;
  int? _windowMinutes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final res = await api.listOnlineNow();
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _error = res.error ?? 'Failed to load');
      return;
    }
    setState(() {
      _online = (res.body['online'] as List).cast<Map<String, dynamic>>();
      _windowMinutes = res.body['windowMinutes'] as int?;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!));
    if (_online == null) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Active in the last ${_windowMinutes ?? 2} minute(s). Pull to refresh.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (_online!.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: Text('No one else is active right now.')),
            )
          else
            for (final u in _online!)
              ListTile(
                leading: Stack(
                  children: [
                    const Icon(Icons.person_outline),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                      ),
                    ),
                  ],
                ),
                title: Text(u['display_name'] as String),
                subtitle: Text(u['email'] as String),
              ),
        ],
      ),
    );
  }
}
