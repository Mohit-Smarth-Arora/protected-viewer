import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../widgets/state_views.dart';
import '../widgets/inline_iframe.dart';
import 'asset_list_screen.dart';

/// Renders a type='html' asset in-app via an iframe pointed at the backend's
/// tokened content URL (see api_client.dart assetContentUrl) — the page
/// keeps its own real behavior (scripts, styles, interactivity) rather than
/// being flattened to an image like 'image'/'snippet' assets are. The
/// server injects a watermark overlay into the HTML itself before serving
/// it (backend/src/lib/watermark.js injectWatermarkIntoHtml) unless this
/// specific viewer's grant has watermark_enabled=0.
///
/// Same token lifecycle as AssetViewerScreen: a fresh short-lived token is
/// requested every time this screen opens, and the iframe is pointed at
/// that URL — nothing is cached or reused across opens.
class HtmlAssetViewerScreen extends StatefulWidget {
  const HtmlAssetViewerScreen({super.key, required this.asset});

  final AssetSummary asset;

  @override
  State<HtmlAssetViewerScreen> createState() => _HtmlAssetViewerScreenState();
}

class _HtmlAssetViewerScreenState extends State<HtmlAssetViewerScreen> {
  String? _contentUrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _contentUrl = null;
    });
    final api = context.read<ApiClient>();
    final tokenRes = await api.requestAssetToken(widget.asset.id);
    if (!mounted) return;
    if (!tokenRes.ok) {
      setState(() => _error = tokenRes.error ?? 'Could not get access to this item');
      return;
    }
    final assetToken = tokenRes.body['token'] as String;
    setState(() => _contentUrl = api.assetContentUrl(widget.asset.id, assetToken));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.asset.title),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Reload', onPressed: _load),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!kIsWeb) {
      // In-app HTML rendering is web-only for now (iframe via
      // dart:ui_web platform views) — Android/iOS would need an actual
      // webview package, deliberately not pulled in until this ships on
      // those platforms too.
      return const EmptyState(
        icon: Icons.web_asset_off_outlined,
        message: 'HTML assets can only be viewed in the web app right now.',
      );
    }
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    if (_contentUrl == null) {
      return const LoadingState();
    }
    return InlineIframe(src: _contentUrl!);
  }
}
