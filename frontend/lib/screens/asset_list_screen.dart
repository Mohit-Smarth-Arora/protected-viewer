import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../theme.dart';
import '../widgets/app_drawer.dart';
import '../widgets/state_views.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_path.isEmpty ? 'Shared with you' : _path.last.$2),
        leading: _path.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => _goToBreadcrumb(_path.length - 2),
              ),
      ),
      drawer: _path.isEmpty ? const AppDrawer() : null,
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: TextField(
        controller: _searchController,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Search this folder',
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildBreadcrumbs() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: scheme.surfaceContainerLow,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _goToBreadcrumb(-1),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(Icons.home_outlined, size: 18, color: scheme.primary),
            ),
          ),
          for (var i = 0; i < _path.length; i++) ...[
            Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _goToBreadcrumb(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  _path[i].$2,
                  style: TextStyle(
                    color: i == _path.length - 1 ? scheme.onSurface : scheme.primary,
                    fontWeight: i == _path.length - 1 ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return ListView(children: [ErrorState(message: _error!, onRetry: _load)]);
    }
    if (_folders == null || _assets == null) {
      return const LoadingState();
    }
    if (_folders!.isEmpty && _assets!.isEmpty) {
      return ListView(
        children: [
          EmptyState(
            icon: Icons.folder_off_outlined,
            message: _path.isEmpty ? 'Nothing has been shared with you yet.' : 'This folder is empty.',
          ),
        ],
      );
    }
    final folders = _filteredFolders;
    final assets = _filteredAssets;
    if (folders.isEmpty && assets.isEmpty) {
      return ListView(children: const [EmptyState(icon: Icons.search_off, message: 'No matches for your search.')]);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        for (final folder in folders)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const TonalIcon(Icons.folder_outlined),
              title: Text(folder.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openFolder(folder),
            ),
          ),
        if (folders.isNotEmpty && assets.isNotEmpty) const SizedBox(height: 8),
        for (final asset in assets)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: TonalIcon(asset.icon),
              title: Text(asset.title),
              subtitle: Text(asset.type),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => AssetViewerScreen(asset: asset)),
                );
              },
            ),
          ),
      ],
    );
  }
}
