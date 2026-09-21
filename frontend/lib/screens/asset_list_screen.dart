import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../state/session.dart';
import 'asset_viewer_screen.dart';
import 'admin_request_screen.dart';
import 'admin_review_screen.dart';
import 'manage_admins_screen.dart';
import 'manage_assets_screen.dart';
import 'user_activity_screen.dart';
import 'chat_screens.dart';
import 'referral_codes_screen.dart';
import 'signup_requests_screen.dart';

class AssetSummary {
  AssetSummary({required this.id, required this.type, required this.title});

  factory AssetSummary.fromJson(Map<String, dynamic> json) => AssetSummary(
        id: json['id'] as String,
        type: json['type'] as String,
        title: json['title'] as String,
      );

  final String id;
  final String type; // 'image' | 'video' | 'snippet'
  final String title;

  IconData get icon => switch (type) {
        'image' => Icons.image_outlined,
        'video' => Icons.videocam_outlined,
        'snippet' => Icons.code_outlined,
        _ => Icons.insert_drive_file_outlined,
      };
}

class FolderSummary {
  FolderSummary({required this.id, required this.name});

  factory FolderSummary.fromJson(Map<String, dynamic> json) => FolderSummary(
        id: json['id'] as String,
        name: json['name'] as String,
      );

  final String id;
  final String name;
}

/// A viewer's (or admin's) browsable view of the shared library — folders
/// work like a simple file browser: tap in, breadcrumb back out. Viewers
/// only ever see folders/assets they've been granted (directly or via an
/// ancestor folder grant); admins/owner see everything. See
/// backend/src/routes/assets.js for the access logic this mirrors.
class AssetListScreen extends StatefulWidget {
  const AssetListScreen({super.key});

  @override
  State<AssetListScreen> createState() => _AssetListScreenState();
}

class _AssetListScreenState extends State<AssetListScreen> {
  List<FolderSummary>? _folders;
  List<AssetSummary>? _assets;
  String? _error;
  final _searchController = TextEditingController();
  String _query = '';

  // Breadcrumb stack: null = root. Each entry is (folderId, folderName).
  final List<(String, String)> _path = [];

  String? get _currentFolderId => _path.isEmpty ? null : _path.last.$1;

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

  List<FolderSummary> get _filteredFolders {
    if (_folders == null) return [];
    if (_query.isEmpty) return _folders!;
    return _folders!.where((f) => f.name.toLowerCase().contains(_query)).toList();
  }

  List<AssetSummary> get _filteredAssets {
    if (_assets == null) return [];
    if (_query.isEmpty) return _assets!;
    return _assets!.where((a) => a.title.toLowerCase().contains(_query)).toList();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final res = await api.listAssets(folderId: _currentFolderId);
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _error = res.error ?? 'Failed to load');
      return;
    }
    final folders = (res.body['folders'] as List)
        .map((f) => FolderSummary.fromJson(f as Map<String, dynamic>))
        .toList();
    final assets = (res.body['assets'] as List)
        .map((a) => AssetSummary.fromJson(a as Map<String, dynamic>))
        .toList();
    setState(() {
      _folders = folders;
      _assets = assets;
      _error = null;
    });
  }

  void _openFolder(FolderSummary folder) {
    setState(() => _path.add((folder.id, folder.name)));
    _load();
  }

  void _goToBreadcrumb(int index) {
    // index == -1 means root
    setState(() => _path.removeRange(index + 1, _path.length));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();

    return Scaffold(
      appBar: AppBar(
        title: Text(_path.isEmpty ? 'Shared with you' : _path.last.$2),
        leading: _path.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => _goToBreadcrumb(_path.length - 2),
              ),
        actions: [_buildMenu(session)],
      ),
      body: Column(
        children: [
          if (_path.isNotEmpty) _buildBreadcrumbs(),
          if ((_folders?.isNotEmpty ?? false) || (_assets?.isNotEmpty ?? false)) _buildSearchBar(),
          Expanded(
            child: RefreshIndicator(onRefresh: _load, child: _buildBody()),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextField(
        controller: _searchController,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Search this folder',
          isDense: true,
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildBreadcrumbs() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          InkWell(onTap: () => _goToBreadcrumb(-1), child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.home, size: 18),
          )),
          for (var i = 0; i < _path.length; i++) ...[
            const Icon(Icons.chevron_right, size: 18),
            InkWell(
              onTap: () => _goToBreadcrumb(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(_path[i].$2),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMenu(Session session) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        switch (value) {
          case 'manage_assets':
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ManageAssetsScreen()),
            );
          case 'manage_admins':
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ManageAdminsScreen()),
            );
          case 'review_requests':
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdminReviewScreen()),
            );
          case 'user_activity':
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UserActivityScreen()),
            );
          case 'signup_requests':
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SignupRequestsScreen()),
            );
          case 'referral_codes':
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReferralCodesScreen()),
            );
          case 'chat_requests':
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ChatRequestsScreen()),
            );
          case 'chat_threads':
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ChatThreadsScreen()),
            );
          case 'request_admin':
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdminRequestScreen()),
            );
          case 'request_chat':
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RequestChatScreen()),
            );
          case 'sign_out':
            session.signOut();
        }
      },
      itemBuilder: (context) => [
        if (session.isAdmin) ...[
          const PopupMenuItem(
            value: 'manage_assets',
            child: ListTile(
              leading: Icon(Icons.folder_shared_outlined),
              title: Text('Manage assets'),
            ),
          ),
          const PopupMenuItem(
            value: 'chat_requests',
            child: ListTile(
              leading: Icon(Icons.mark_chat_unread_outlined),
              title: Text('Chat requests'),
            ),
          ),
          const PopupMenuItem(
            value: 'chat_threads',
            child: ListTile(
              leading: Icon(Icons.chat_outlined),
              title: Text('Messages'),
            ),
          ),
          const PopupMenuItem(
            value: 'user_activity',
            child: ListTile(
              leading: Icon(Icons.people_outline),
              title: Text('Users & activity'),
            ),
          ),
          const PopupMenuItem(
            value: 'signup_requests',
            child: ListTile(
              leading: Icon(Icons.how_to_reg_outlined),
              title: Text('Signup requests'),
            ),
          ),
        ],
        if (session.effectiveMasterAccess) ...[
          const PopupMenuItem(
            value: 'review_requests',
            child: ListTile(
              leading: Icon(Icons.fact_check_outlined),
              title: Text('Review admin requests'),
            ),
          ),
          const PopupMenuItem(
            value: 'manage_admins',
            child: ListTile(
              leading: Icon(Icons.admin_panel_settings_outlined),
              title: Text('Manage admins'),
            ),
          ),
          const PopupMenuItem(
            value: 'referral_codes',
            child: ListTile(
              leading: Icon(Icons.qr_code),
              title: Text('Referral codes'),
            ),
          ),
        ],
        if (!session.isAdmin) ...[
          const PopupMenuItem(
            value: 'request_chat',
            child: ListTile(
              leading: Icon(Icons.chat_bubble_outline),
              title: Text('Message an admin'),
            ),
          ),
          const PopupMenuItem(
            value: 'request_admin',
            child: ListTile(
              leading: Icon(Icons.upgrade_outlined),
              title: Text('Request admin access'),
            ),
          ),
        ],
        PopupMenuItem(
          value: 'sign_out',
          child: ListTile(
            leading: const Icon(Icons.logout),
            title: Text('Sign out (${session.userEmail ?? ''})'),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Icon(Icons.error_outline, size: 40, color: Colors.red.shade300),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
        ],
      );
    }
    if (_folders == null || _assets == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_folders!.isEmpty && _assets!.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Text(
              _path.isEmpty ? 'Nothing has been shared with you yet.' : 'This folder is empty.',
            ),
          ),
        ],
      );
    }
    final folders = _filteredFolders;
    final assets = _filteredAssets;
    if (folders.isEmpty && assets.isEmpty) {
      return ListView(
        children: const [SizedBox(height: 80), Center(child: Text('No matches for your search.'))],
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final folder in folders)
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(folder.name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openFolder(folder),
          ),
        if (folders.isNotEmpty && assets.isNotEmpty) const Divider(height: 1),
        for (final asset in assets)
          ListTile(
            leading: Icon(asset.icon),
            title: Text(asset.title),
            subtitle: Text(asset.type),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AssetViewerScreen(asset: asset)),
              );
            },
          ),
      ],
    );
  }
}
