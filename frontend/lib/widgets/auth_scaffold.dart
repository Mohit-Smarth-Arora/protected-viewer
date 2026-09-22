import 'package:flutter/material.dart';

/// Shared visual shell for the pre-signed-in / gate screens (login,
/// email verification, pending approval, agreement). Gives the app an
/// actual identity on first impression instead of a bare centered card on
/// a blank scaffold — a soft brand-colored backdrop behind a elevated card.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.child,
    this.maxWidth = 420,
    this.appBar,
  });

  final Widget child;
  final double maxWidth;
  final PreferredSizeWidget? appBar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: appBar,
      extendBodyBehindAppBar: appBar != null,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [scheme.surface, scheme.surface]
                : [scheme.primaryContainer.withValues(alpha: 0.35), scheme.surface],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Card(
                  elevation: 0,
                  color: scheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The shield-in-tonal-circle brand mark, used at the top of auth screens.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.icon = Icons.shield_outlined, this.size = 56});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.5, color: scheme.onPrimaryContainer),
    );
  }
}
