// Conditional export: the real iframe-backed implementation
// (inline_iframe_web.dart) imports dart:ui_web and package:web, both of
// which only exist on the web compiler target — they fail to even compile
// on the VM (used by `flutter test` and any future native Android/iOS
// build), not just fail at runtime. The dart.library.js_interop check
// picks the real implementation when compiling for web and the inert
// stub (inline_iframe_stub.dart) everywhere else, so importing this file
// is always safe regardless of target platform.
export 'inline_iframe_stub.dart' if (dart.library.js_interop) 'inline_iframe_web.dart';
