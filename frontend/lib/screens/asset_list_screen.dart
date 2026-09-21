import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../state/session.dart';
import 'asset_viewer_screen.dart';
import 'admin_request_screen.dart';
import 'admin_review_screen.dart';
import 'manage_admins_screen.dart';
import 'manage_assets_screen.dart';

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

class AssetListScreen extends StatefulWidget {
  const AssetListScreen({super.key});

  @override
  State<AssetListScreen> createState() => _AssetListScreenState();
}

class _AssetListScreenState extends State<AssetListScreen> {
  List<AssetSummary>? _assets;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final res = await api.listAssets();
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _error = res.error ?? 'Failed to load assets');
      return;
    }
    final list = (res.body['assets'] as List)
        .map((a) => AssetSummary.fromJson(a as Map<String, dynamic>))
        .toList();
    setState(() {
      _assets = list;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared with you'),
        actions: [
          PopupMenuButton<String>(
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
                case 'request_admin':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdminRequestScreen()),
                  );
                case 'sign_out':
                  session.signOut();
              }
            },
            itemBuilder: (context) => [
              if (session.isAdmin)
                const PopupMenuItem(
                  value: 'manage_assets',
                  child: ListTile(
                    leading: Icon(Icons.folder_shared_outlined),
                    title: Text('Manage assets'),
                  ),
                ),
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
              ],
              if (!session.isAdmin)
                const PopupMenuItem(
                  value: 'request_admin',
                  child: ListTile(
                    leading: Icon(Icons.upgrade_outlined),
                    title: Text('Request admin access'),
                  ),
                ),
              PopupMenuItem(
                value: 'sign_out',
                child: ListTile(
                  leading: const Icon(Icons.logout),
                  title: Text('Sign out (${session.userEmail ?? ''})'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
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
    if (_assets == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_assets!.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Center(child: Text('Nothing has been shared with you yet.')),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _assets!.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final asset = _assets![i];
        return ListTile(
          leading: Icon(asset.icon),
          title: Text(asset.title),
          subtitle: Text(asset.type),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AssetViewerScreen(asset: asset),
              ),
            );
          },
        );
      },
    );
  }
}
