import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Renders already-watermarked PNG bytes via a raw [CustomPainter] onto a
/// [Canvas], rather than [Image.memory] inside a normal widget tree.
///
/// Why this matters: a plain `Image` widget still exposes a right-clickable
/// `<img>`-like target in some contexts and is a very standard "save image"
/// affordance for users/extensions to hook. Painting it ourselves onto a
/// canvas means there's no image element for a browser's native "save
/// image as" context menu to attach to — the pixels are just draw calls.
///
/// This is UX friction, not real security (see backend/README.md threat
/// model) — the actual protection is that the bytes arriving here are
/// already watermarked server-side. This widget's job is just to not make
/// casual copying *easier* than it has to be.
class ProtectedImageView extends StatefulWidget {
  const ProtectedImageView({super.key, required this.pngBytes});

  final Uint8List pngBytes;

  @override
  State<ProtectedImageView> createState() => _ProtectedImageViewState();
}

class _ProtectedImageViewState extends State<ProtectedImageView> {
  ui.Image? _decodedImage;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(covariant ProtectedImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pngBytes != widget.pngBytes) {
      _decode();
    }
  }

  Future<void> _decode() async {
    final codec = await ui.instantiateImageCodec(widget.pngBytes);
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _decodedImage = frame.image);
  }

  @override
  void dispose() {
    _decodedImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _decodedImage;
    if (image == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: GestureDetector(
        // Swallow long-press (mobile "save image" trigger) and secondary-tap
        // (desktop right-click context menu) rather than letting them
        // reach any default handler.
        onLongPress: () {},
        onSecondaryTap: () {},
        child: Listener(
          onPointerDown: (_) {},
          child: SelectionContainer.disabled(
            child: FittedBox(
              child: SizedBox(
                width: image.width.toDouble(),
                height: image.height.toDouble(),
                child: CustomPaint(
                  painter: _ImagePainter(image),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImagePainter extends CustomPainter {
  _ImagePainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(image, Offset.zero, Paint());
  }

  @override
  bool shouldRepaint(covariant _ImagePainter oldDelegate) => oldDelegate.image != image;
}
