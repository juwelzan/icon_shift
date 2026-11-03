import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'config.dart';

/// Downloads [url]. Throws on any failure.
typedef RemoteFetch =
    Future<Uint8List> Function(Uri url, {required int maxBytes});

const _maxImageBytes = 10 * 1024 * 1024;
const _maxManifestBytes = 512 * 1024;

/// Result of [resolveRemote]: the config with every URL replaced by a
/// downloaded file, and what happened.
class RemoteResolution {
  RemoteResolution(this.config, this.messages);
  final GeneratorConfig config;
  final List<String> messages;
}

/// Thrown when a remote manifest or image cannot be used.
class RemoteException extends ConfigException {
  RemoteException(super.message);
}

/// Merges the variants of `remote.manifest` into [config] and downloads every
/// `https://` image into `remote.assets_dir`, so the rest of the generator
/// (and the Flutter build) only sees local files.
///
/// Downloads are named after a hash of their URL and reused on later runs;
/// pass [refresh] to download them again (e.g. when the server replaced an
/// image at the same URL). Variants defined in icon_shift.yaml win over
/// manifest variants with the same id.
Future<RemoteResolution> resolveRemote(
  String projectDir,
  GeneratorConfig config, {
  bool refresh = false,
  RemoteFetch? fetch,
}) async {
  final get = fetch ?? httpGet;
  final messages = <String>[];
  var resolved = config;

  if (config.remote.manifest case final manifest?) {
    final url = Uri.parse(manifest);
    final Object? json;
    try {
      final bytes = await get(url, maxBytes: _maxManifestBytes);
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (e) {
      throw RemoteException(
        'Remote manifest $url is not valid JSON: ${e.message}',
      );
    } on ConfigException {
      rethrow;
    } on Object catch (e) {
      throw RemoteException('Could not download the remote manifest $url: $e');
    }
    final remoteVariants = GeneratorConfig.parseRemoteVariants(json, url);
    final merged = {...config.variants};
    remoteVariants.forEach((id, spec) {
      if (merged.containsKey(id)) {
        messages.add(
          'remote: variant "$id" is also defined in icon_shift.yaml; '
          'the local definition is used.',
        );
      } else {
        merged[id] = spec;
      }
    });
    messages.add(
      'remote: ${remoteVariants.length} variant(s) from $url '
      '(${remoteVariants.keys.join(', ')}).',
    );
    resolved = resolved.copyWith(variants: merged);
  }

  final urls = resolved.allIcons.where(isRemoteSource).toSet();
  if (urls.isEmpty) return RemoteResolution(resolved, messages);

  final dir = Directory(p.join(projectDir, config.remote.assetsDir));
  final local = <String, String>{};
  var downloaded = 0;
  for (final source in urls) {
    final url = Uri.parse(source);
    final base = 'r_${fnv1a64(source)}';
    final existing = _cached(dir, base);
    if (existing != null && !refresh) {
      local[source] = p.posix.join(config.remote.assetsDir, existing);
      continue;
    }
    final Uint8List bytes;
    try {
      bytes = await get(url, maxBytes: _maxImageBytes);
    } on Object catch (e) {
      throw RemoteException('Could not download $url: $e');
    }
    final ext = _imageExtension(bytes);
    if (ext == null) {
      throw RemoteException(
        '$url is not a PNG or JPEG image (SVG and other formats cannot be '
        'used for app icons).',
      );
    }
    dir.createSync(recursive: true);
    if (existing != null) File(p.join(dir.path, existing)).deleteSync();
    File(p.join(dir.path, '$base.$ext')).writeAsBytesSync(bytes);
    local[source] = p.posix.join(config.remote.assetsDir, '$base.$ext');
    downloaded++;
  }
  messages.add(
    'remote: ${urls.length} image(s) in ${config.remote.assetsDir} '
    '($downloaded downloaded, ${urls.length - downloaded} cached'
    '${refresh ? '' : '; --refresh-remote downloads them again'}).',
  );
  return RemoteResolution(
    resolved.copyWith(mapImages: (v) => local[v] ?? v),
    messages,
  );
}

/// Default [RemoteFetch]: GET with redirects, https-only redirects, limits.
Future<Uint8List> httpGet(Uri url, {required int maxBytes}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..userAgent = 'icon_shift_cli';
  try {
    final response = await (await client.getUrl(url)).close();
    final finalUrl = response.redirects.isEmpty
        ? url
        : response.redirects.last.location;
    if (url.isScheme('https') && !finalUrl.isScheme('https')) {
      throw HttpException('redirected to a non-https URL', uri: finalUrl);
    }
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
      if (builder.length > maxBytes) {
        throw HttpException('larger than $maxBytes bytes', uri: url);
      }
    }
    return builder.takeBytes();
  } finally {
    client.close(force: true);
  }
}

String? _cached(Directory dir, String base) {
  for (final ext in ['png', 'jpg']) {
    if (File(p.join(dir.path, '$base.$ext')).existsSync()) return '$base.$ext';
  }
  return null;
}

String? _imageExtension(Uint8List b) {
  if (b.length > 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E) {
    return 'png';
  }
  if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return 'jpg';
  }
  return null;
}

/// Stable 64-bit FNV-1a hash as 16 hex digits (file names, Xcode ids).
String fnv1a64(String value) {
  // 32-bit halves keep the intermediate products below 2^63.
  var hi = 0xcbf29ce4, lo = 0x84222325;
  for (final byte in utf8.encode(value)) {
    lo ^= byte;
    // Multiply by the FNV prime 0x100000001b3.
    final loMul = lo * 0x1b3;
    final carry = loMul ~/ 0x100000000;
    hi = (hi * 0x1b3 + (lo << 8) + carry) & 0xffffffff;
    lo = loMul & 0xffffffff;
  }
  return hi.toRadixString(16).padLeft(8, '0') +
      lo.toRadixString(16).padLeft(8, '0');
}
