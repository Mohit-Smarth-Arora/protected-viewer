import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';

class AdminAssetSummary {
  AdminAssetSummary.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        type = json['type'] as String,
        title = json['title'] as String,
        uploadedByName = json['uploaded_by_name'] as String?;

  final String id;
  final String type;
  final String title;
  final String? uploadedByName;
}

class AdminFolderSummary {
  AdminFolderSummary.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        name = json['name'] as String;

  final String id;
  final String name;
}

/// Plain-admin-and-up screen: browse/create/rename/delete folders, upload
/// new assets into the current folder, delete assets, and manage per-viewer
/// grants at both the folder and asset level. Mirrors AssetListScreen's
/// browsing model but with admin controls layered on.
class ManageAssetsScreen extends StatefulWidget {
  const ManageAssetsScreen({super.key});

  @override
  State<ManageAssetsScreen> createState() => _ManageAssetsScreenState();
}

class _ManageAssetsScreenState extends State<ManageAssetsScreen> {
  List<AdminFolderSummary>? _folders;
  List<AdminAssetSummary>? _assets;
  String? _error;

  final List<(String, String)> _path = [];
  String? get _currentFolderId => _path.isEmpty ? null : _path.last.$1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final res = await api.listAssets(folderId: _currentFolderId);
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _error = res.error ?? 'Failed to load');
      return;
    }
    setState(() {
      _folders = (res.body['folders'] as List)
          .map((f) => AdminFolderSummary.fromJson(f as Map<String, dynamic>))
          .toList();
      _assets = (res.body['assets'] as List)
          .map((a) => AdminAssetSummary.fromJson(a as Map<String, dynamic>))
          .toList();
      _error = null;
    });
  }

  void _openFolder(AdminFolderSummary folder) {
    setState(() => _path.add((folder.id, folder.name)));
    _load();
  }

  void _goToBreadcrumb(int index) {
    setState(() => _path.removeRange(index + 1, _path.length));
    _load();
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Folder name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;

    final api = context.read<ApiClient>();
    final res = await api.createFolder(name: name, parentId: _currentFolderId);
    if (!mounted) return;
    if (res.ok) {
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error ?? 'Could not create folder')));
    }
  }

  Future<void> _renameFolder(AdminFolderSummary folder) async {
    final controller = TextEditingController(text: folder.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename folder'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == folder.name || !mounted) return;

    final api = context.read<ApiClient>();
    final res = await api.renameFolder(folder.id, name);
    if (!mounted) return;
    if (res.ok) _load();
  }

  Future<void> _deleteFolder(AdminFolderSummary folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${folder.name}"?'),
        content: const Text(
          'This deletes the folder, everything inside it (subfolders and assets), and all related access grants. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final api = context.read<ApiClient>();
    final res = await api.deleteFolder(folder.id);
    if (!mounted) return;
    if (res.ok) {
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error ?? 'Delete failed')));
    }
  }

  Future<void> _manageFolderGrants(AdminFolderSummary folder) async {
    await showDialog(
      context: context,
      builder: (_) => _FolderGrantsDialog(folder: folder),
    );
  }

  Future<void> _showUploadDialog() async {
    await showDialog(
      context: context,
      builder: (_) => _UploadAssetDialog(folderId: _currentFolderId, onUploaded: _load),
    );
  }

  Future<void> _deleteAsset(AdminAssetSummary asset) async {
    final api = context.read<ApiClient>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${asset.title}"?'),
        content: const Text('This removes the asset and all viewer grants for it. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;

    final res = await api.deleteAsset(asset.id);
    if (!mounted) return;
    if (res.ok) {
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error ?? 'Delete failed')));
    }
  }

  Future<void> _manageAssetGrants(AdminAssetSummary asset) async {
    await showDialog(
      context: context,
      builder: (_) => _AssetGrantsDialog(asset: asset),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_path.isEmpty ? 'Manage assets' : _path.last.$2),
        leading: _path.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => _goToBreadcrumb(_path.length - 2),
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'New folder',
            onPressed: _createFolder,
          ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Upload asset here',
            onPressed: _showUploadDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_path.isNotEmpty) _buildBreadcrumbs(),
          Expanded(child: RefreshIndicator(onRefresh: _load, child: _buildBody())),
        ],
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
          InkWell(
            onTap: () => _goToBreadcrumb(-1),
            child: const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.home, size: 18)),
          ),
          for (var i = 0; i < _path.length; i++) ...[
            const Icon(Icons.chevron_right, size: 18),
            InkWell(
              onTap: () => _goToBreadcrumb(i),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(_path[i].$2)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return ListView(children: [const SizedBox(height: 60), Center(child: Text(_error!))]);
    }
    if (_folders == null || _assets == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_folders!.isEmpty && _assets!.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 60),
          Center(child: Text('Empty. Create a folder or upload an asset.')),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final folder in _folders!)
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(folder.name),
            onTap: () => _openFolder(folder),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'access':
                    _manageFolderGrants(folder);
                  case 'rename':
                    _renameFolder(folder);
                  case 'delete':
                    _deleteFolder(folder);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'access', child: Text('Manage access')),
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ),
        if (_folders!.isNotEmpty && _assets!.isNotEmpty) const Divider(height: 1),
        for (final asset in _assets!)
          ListTile(
            leading: Icon(asset.type == 'image' ? Icons.image_outlined : Icons.code_outlined),
            title: Text(asset.title),
            subtitle: Text('${asset.type}${asset.uploadedByName != null ? " • by ${asset.uploadedByName}" : ""}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.people_outline),
                  tooltip: 'Manage access',
                  onPressed: () => _manageAssetGrants(asset),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                  onPressed: () => _deleteAsset(asset),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _UploadAssetDialog extends StatefulWidget {
  const _UploadAssetDialog({required this.onUploaded, this.folderId});

  final VoidCallback onUploaded;
  final String? folderId;

  @override
  State<_UploadAssetDialog> createState() => _UploadAssetDialogState();
}

class _UploadAssetDialogState extends State<_UploadAssetDialog> {
  final _titleController = TextEditingController();
  String _type = 'image';
  PlatformFile? _file;
  bool _isUploading = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: _type == 'image' ? FileType.image : FileType.any,
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _file = result.files.first);
    }
  }

  Future<void> _upload() async {
    if (_titleController.text.trim().isEmpty) {
      setState(() => _error = 'Title is required');
      return;
    }
    if (_file == null || _file!.bytes == null) {
      setState(() => _error = 'Please select a file');
      return;
    }
    setState(() {
      _isUploading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    final res = await api.uploadAsset(
      type: _type,
      title: _titleController.text.trim(),
      fileBytes: _file!.bytes!,
      filename: _file!.name,
    );
    if (!mounted) return;
    setState(() => _isUploading = false);
    if (res.ok) {
      widget.onUploaded();
      Navigator.of(context).pop();
    } else {
      setState(() => _error = res.error ?? 'Upload failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Upload asset'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'image', label: Text('Image')),
                ButtonSegment(value: 'snippet', label: Text('Python snippet')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() {
                _type = s.first;
                _file = null;
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.attach_file),
              label: Text(_file == null ? 'Select file' : _file!.name),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isUploading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isUploading ? null : _upload,
          child: _isUploading
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Upload'),
        ),
      ],
    );
  }
}

class _ViewerOption {
  _ViewerOption.fromJson(Map<String, dynamic> json)
      : id = json['id'] as int,
        email = json['email'] as String,
        displayName = json['display_name'] as String;

  final int id;
  final String email;
  final String displayName;
}

class _AssetGrantsDialog extends StatefulWidget {
  const _AssetGrantsDialog({required this.asset});

  final AdminAssetSummary asset;

  @override
  State<_AssetGrantsDialog> createState() => _AssetGrantsDialogState();
}

class _AssetGrantsDialogState extends State<_AssetGrantsDialog> {
  List<_ViewerOption>? _allViewers;
  Set<int> _grantedUserIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final usersRes = await api.listViewers();
    final grantsRes = await api.listAssetGrants(widget.asset.id);
    if (!mounted) return;

    final viewers = usersRes.ok
        ? (usersRes.body['users'] as List).map((u) => _ViewerOption.fromJson(u as Map<String, dynamic>)).toList()
        : <_ViewerOption>[];
    final granted =
        grantsRes.ok ? (grantsRes.body['grants'] as List).map((g) => g['user_id'] as int).toSet() : <int>{};

    setState(() {
      _allViewers = viewers;
      _grantedUserIds = granted;
      _loading = false;
    });
  }

  Future<void> _toggle(_ViewerOption viewer, bool grant) async {
    final api = context.read<ApiClient>();
    final res = grant
        ? await api.grantAsset(widget.asset.id, viewer.id)
        : await api.revokeAssetGrant(widget.asset.id, viewer.id);
    if (!mounted) return;
    if (res.ok) {
      setState(() {
        if (grant) {
          _grantedUserIds.add(viewer.id);
        } else {
          _grantedUserIds.remove(viewer.id);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Access to "${widget.asset.title}"'),
      content: SizedBox(
        width: 360,
        height: 400,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_allViewers!.isEmpty
                ? const Center(child: Text('No viewer accounts exist yet.'))
                : ListView.builder(
                    itemCount: _allViewers!.length,
                    itemBuilder: (context, i) {
                      final viewer = _allViewers![i];
                      final granted = _grantedUserIds.contains(viewer.id);
                      return CheckboxListTile(
                        value: granted,
                        title: Text(viewer.displayName),
                        subtitle: Text(viewer.email),
                        onChanged: (value) => _toggle(viewer, value ?? false),
                      );
                    },
                  )),
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ],
    );
  }
}

class _FolderGrantsDialog extends StatefulWidget {
  const _FolderGrantsDialog({required this.folder});

  final AdminFolderSummary folder;

  @override
  State<_FolderGrantsDialog> createState() => _FolderGrantsDialogState();
}

class _FolderGrantsDialogState extends State<_FolderGrantsDialog> {
  List<_ViewerOption>? _allViewers;
  Set<int> _grantedUserIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final usersRes = await api.listViewers();
    final grantsRes = await api.listFolderGrants(widget.folder.id);
    if (!mounted) return;

    final viewers = usersRes.ok
        ? (usersRes.body['users'] as List).map((u) => _ViewerOption.fromJson(u as Map<String, dynamic>)).toList()
        : <_ViewerOption>[];
    final granted =
        grantsRes.ok ? (grantsRes.body['grants'] as List).map((g) => g['user_id'] as int).toSet() : <int>{};

    setState(() {
      _allViewers = viewers;
      _grantedUserIds = granted;
      _loading = false;
    });
  }

  Future<void> _toggle(_ViewerOption viewer, bool grant) async {
    final api = context.read<ApiClient>();
    final res = grant
        ? await api.grantFolder(widget.folder.id, viewer.id)
        : await api.revokeFolderGrant(widget.folder.id, viewer.id);
    if (!mounted) return;
    if (res.ok) {
      setState(() {
        if (grant) {
          _grantedUserIds.add(viewer.id);
        } else {
          _grantedUserIds.remove(viewer.id);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Access to "${widget.folder.name}"'),
      content: SizedBox(
        width: 360,
        height: 400,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Granting this folder also grants everything inside it, including subfolders.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: _allViewers!.isEmpty
                        ? const Center(child: Text('No viewer accounts exist yet.'))
                        : ListView.builder(
                            itemCount: _allViewers!.length,
                            itemBuilder: (context, i) {
                              final viewer = _allViewers![i];
                              final granted = _grantedUserIds.contains(viewer.id);
                              return CheckboxListTile(
                                value: granted,
                                title: Text(viewer.displayName),
                                subtitle: Text(viewer.email),
                                onChanged: (value) => _toggle(viewer, value ?? false),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ],
    );
  }
}
