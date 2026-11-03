// Downloads for remote icons: dart:io's HttpClient on native platforms, the
// browser's fetch() on web. No HTTP package dependency is needed.
export 'http_fetch_io.dart' if (dart.library.js_interop) 'http_fetch_web.dart';
