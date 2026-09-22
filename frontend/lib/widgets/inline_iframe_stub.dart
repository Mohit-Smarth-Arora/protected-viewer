import 'package:flutter/material.dart';

/// Non-web fallback for InlineIframe — there is no iframe equivalent on
/// native/VM targets. html_asset_viewer_screen.dart already checks
/// kIsWeb and shows its own "not supported here" message before ever
/// building this widget, so in practice this body never renders; it
/// exists only so the conditional-imported `inline_iframe.dart` API has
/// a valid implementation on every platform, including the `flutter test`
/// VM runner (which cannot compile dart:ui_web / package:web at all —
/// see git history for the CI failure this fixes).
class InlineIframe extends StatelessWidget {
  const InlineIframe({super.key, required this.src});

  final String src;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
