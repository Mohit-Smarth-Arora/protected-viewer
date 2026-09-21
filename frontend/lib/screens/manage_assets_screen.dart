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

/// Plain-admin-and-up screen: upload new assets (image/snippet), delete
/// assets, and manage per-viewer grants. Reachable by any admin — no
/// master access required, per the tiered model.
class ManageAssetsScreen extends StatefulWidget {
  const ManageAssetsScreen({super.key});

  @override
  State<ManageAssetsScreen> createState() => _ManageAssetsScreenState();
}

class _ManageAssetsScreenState extends State<ManageAssetsScreen> {
  List<AdminAssetSummary>? _assets;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final res = await api.listAdminAssets();
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _error = res.error ?? 'Failed to load assets');
      return;
    }
    final list = (res.body['assets'] as List)
        .map((a) => AdminAssetSummary.fromJson(a as Map<String, dynamic>))
        .toList();
    setState(() {
      _assets = list;
      _error = null;
    });
  }

  Future<void> _showUploadDialog() async {
    await showDialog(
      context: context,
      builder: (_) => _UploadAssetDialog(onUploaded: _load),
    );
  }

  Future<void> _delete(AdminAssetSummary asset) async {
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

  Future<void> _manageGrants(AdminAssetSummary asset) async {
    await showDialog(
      context: context,
      builder: (_) => _GrantsDialog(asset: asset),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage assets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Upload asset',
            onPressed: _showUploadDialog,
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showUploadDialog,
        icon: const Icon(Icons.add),
        label: const Text('Upload'),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return ListView(children: [const SizedBox(height: 60), Center(child: Text(_error!))]);
    }
    if (_assets == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_assets!.isEmpty) {
      return ListView(
        children: const [SizedBox(height: 60), Center(child: Text('No assets uploaded yet.'))],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _assets!.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final asset = _assets![i];
        return ListTile(
          leading: Icon(asset.type == 'image' ? Icons.image_outlined : Icons.code_outlined),
          title: Text(asset.title),
          subtitle: Text('${asset.type}${asset.uploadedByName != null ? " • by ${asset.uploadedByName}" : ""}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.people_outline),
                tooltip: 'Manage access',
                onPressed: () => _manageGrants(asset),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
                onPressed: () => _delete(asset),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UploadAssetDialog extends StatefulWidget {
  const _UploadAssetDialog({required this.onUploaded});

  final VoidCallback onUploaded;

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

class _GrantsDialog extends StatefulWidget {
  const _GrantsDialog({required this.asset});

  final AdminAssetSummary asset;

  @override
  State<_GrantsDialog> createState() => _GrantsDialogState();
}

class _GrantsDialogState extends State<_GrantsDialog> {
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
        ? (usersRes.body['users'] as List)
            .map((u) => _ViewerOption.fromJson(u as Map<String, dynamic>))
            .toList()
        : <_ViewerOption>[];
    final granted = grantsRes.ok
        ? (grantsRes.body['grants'] as List).map((g) => g['user_id'] as int).toSet()
        : <int>{};

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
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
