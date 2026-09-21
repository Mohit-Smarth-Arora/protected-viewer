import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../state/session.dart';
import 'asset_viewer_screen.dart';

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
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out (${session.userEmail ?? ''})',
            onPressed: () => session.signOut(),
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
