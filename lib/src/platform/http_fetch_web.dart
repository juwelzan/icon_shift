import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// GETs [url] with the browser's fetch(); the server must allow CORS.
Future<Uint8List> httpGetBytes(
  Uri url, {
  required int maxBytes,
  Duration timeout = const Duration(seconds: 15),
  Map<String, String> headers = const {},
}) async {
  final response = await web.window
      .fetch(
        url.toString().toJS,
        web.RequestInit(
          headers: headers.entries.fold<web.Headers>(web.Headers(), (h, e) {
            h.set(e.key, e.value);
            return h;
          }),
        ),
      )
      .toDart
      .timeout(timeout);
  if (!response.ok) {
    throw StateError('HTTP ${response.status} for $url');
  }
  final buffer = await response.arrayBuffer().toDart.timeout(timeout);
  final bytes = buffer.toDart.asUint8List();
  if (bytes.length > maxBytes) {
    throw StateError('Response exceeds $maxBytes bytes: $url');
  }
  return bytes;
}
