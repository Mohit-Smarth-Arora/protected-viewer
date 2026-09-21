import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../widgets/protected_image_view.dart';
import 'asset_list_screen.dart';

/// Fetches a short-lived per-asset token, then the watermarked bytes for
/// that token, and displays them. Every open of this screen is a fresh
/// token + fresh fetch — nothing is cached client-side, matching the
/// "no-store" cache header the backend sends (backend/src/routes/assets.js).
class AssetViewerScreen extends StatefulWidget {
  const AssetViewerScreen({super.key, required this.asset});

  final AssetSummary asset;

  @override
  State<AssetViewerScreen> createState() => _AssetViewerScreenState();
}

class _AssetViewerScreenState extends State<AssetViewerScreen> {
  Uint8List? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();

    final tokenRes = await api.requestAssetToken(widget.asset.id);
    if (!mounted) return;
    if (!tokenRes.ok) {
      setState(() => _error = tokenRes.error ?? 'Could not get access to this item');
      return;
    }
    final assetToken = tokenRes.body['token'] as String;

    final contentRes = await api.fetchAssetContent(widget.asset.id, assetToken);
    if (!mounted) return;
    if (contentRes.statusCode != 200) {
      setState(() => _error = 'Could not load this item (status ${contentRes.statusCode})');
      return;
    }
    setState(() => _bytes = contentRes.bodyBytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.asset.title)),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 40, color: Colors.red.shade300),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_bytes == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Both 'image' and 'snippet' asset types arrive as watermarked PNG
    // bytes from the backend — snippets are rendered server-side to an
    // image so raw source text is never sent to this client. Same viewer
    // handles both for now; a dedicated video player lands separately once
    // the backend's video pipeline exists.
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(16),
      child: ProtectedImageView(pngBytes: _bytes!),
    );
  }
}
