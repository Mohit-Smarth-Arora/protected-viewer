import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Embeds an external URL in-app via an HTML <iframe>, registered as a
/// Flutter Web platform view. This is the Flutter-Web equivalent of
/// "open in the same tab, not a new one" — the page renders inside this
/// app's own layout instead of navigating the browser away from it.
///
/// Native (non-web) targets have no iframe equivalent; this widget is only
/// ever built behind a kIsWeb check by its caller (see
/// html_asset_viewer_screen.dart), so no native fallback is implemented here.
class InlineIframe extends StatefulWidget {
  const InlineIframe({super.key, required this.src});

  final String src;

  @override
  State<InlineIframe> createState() => _InlineIframeState();
}

class _InlineIframeState extends State<InlineIframe> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    // Unique per widget instance (not per URL) so re-opening the same asset
    // — e.g. after a token expired and this screen reloaded with a fresh
    // token — always gets a fresh iframe element rather than a stale
    // registration pointing at an old, now-expired URL.
    _viewType = 'protected-viewer-iframe-${identityHashCode(this)}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final element = web.HTMLIFrameElement()
        ..src = widget.src
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        // No special sandbox permissions beyond the default — this is
        // trusted first-party content (uploaded by an admin through this
        // app's own upload path), not arbitrary third-party embeds.
        ..setAttribute('title', 'Protected content');
      return element;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
