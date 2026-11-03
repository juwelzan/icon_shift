import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// GETs [url] and returns the body, refusing redirects to non-https URLs,
/// non-200 responses and bodies over [maxBytes].
Future<Uint8List> httpGetBytes(
  Uri url, {
  required int maxBytes,
  Duration timeout = const Duration(seconds: 15),
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(url).timeout(timeout);
    request.followRedirects = true;
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(timeout);
    final finalUrl = response.redirects.isEmpty
        ? url
        : response.redirects.last.location;
    if (finalUrl.isScheme('http') && !url.isScheme('http')) {
      throw HttpException('Redirected from https to http', uri: finalUrl);
    }
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    if (response.contentLength > maxBytes) {
      throw HttpException(
        'Response is ${response.contentLength} bytes (limit $maxBytes)',
        uri: url,
      );
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(timeout)) {
      builder.add(chunk);
      if (builder.length > maxBytes) {
        throw HttpException('Response exceeds $maxBytes bytes', uri: url);
      }
    }
    return builder.takeBytes();
  } finally {
    client.close(force: true);
  }
}
