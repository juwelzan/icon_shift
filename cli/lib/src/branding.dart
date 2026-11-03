import 'dart:convert';
import 'dart:typed_data';

import 'config.dart';
import 'remote.dart' show RemoteFetch, httpGet;

/// Largest branding document accepted from a server.
const int maxBrandingBytes = 256 * 1024;

/// One institution's branding, as the school's own server publishes it.
///
/// DigiEdu / Schoolmate serves every school from its own host, and the
/// bootstrap endpoint needs no login:
///
/// ```
/// GET https://<school>.digiedu.online/api/v1/branding
/// {"data":{"app_name":"…","logo_url":null,"favicon_url":null,
///          "primary_color":"#1e40af","secondary_color":"#3b82f6",
///          "app_code":"588846"},"message":"…"}
/// ```
///
/// The runtime side parses the same document into `BrandingProfile`; this is
/// the build-time half, used to produce a branded APK/AAB or IPA.
class InstitutionBranding {
  InstitutionBranding({
    required this.tenantId,
    this.appName,
    this.logoUrl,
    this.launcherIconUrl,
    this.primaryColor,
    this.secondaryColor,
    this.appCode,
  });

  /// The school host; also the slug the build is named after.
  final String tenantId;

  final String? appName;
  final String? logoUrl;

  /// The image to turn into launcher icons, when the server sends one.
  final String? launcherIconUrl;

  /// `#RRGGBB`.
  final String? primaryColor;
  final String? secondaryColor;
  final String? appCode;

  /// The icon to build from: a dedicated launcher icon, else the logo.
  String? get iconSource => launcherIconUrl ?? logoUrl;

  /// Lowercase, `[a-z0-9_]`, derived from the host:
  /// `abc-school.digiedu.online` → `abc_school`. Used for the build profile,
  /// artifact names and the Android applicationId.
  String get slug {
    final host = tenantId.split('.').first;
    final cleaned = host
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '_')
        .replaceAll(RegExp('^_+|_+\$'), '');
    final safe = cleaned.isEmpty ? 'school' : cleaned;
    return RegExp('^[a-z]').hasMatch(safe) ? safe : 's_$safe';
  }

  /// [slug] for Apple bundle ids, which allow `-` but not `_`:
  /// `abc_school` → `abc-school`.
  String get appleSlug => slug.replaceAll('_', '-');

  /// Parses the bootstrap response for the school at [tenantId].
  ///
  /// A `data` envelope is unwrapped, and `institution_name`/`name`,
  /// `launcher_icon_url`/`icon_url`/`favicon_url` and
  /// `institution_id`/`tenant_id` are accepted as aliases, so another back
  /// end needs no adapter. Values that are not usable for a build (a name
  /// with control characters, a non-https URL, a malformed colour) are
  /// rejected with a [ConfigException] rather than silently built in.
  factory InstitutionBranding.parse(Object? json, {required String tenantId}) {
    if (json is! Map) {
      throw ConfigException('The branding response must be a JSON object.');
    }
    final envelope = json['data'];
    final map = <String, Object?>{
      for (final MapEntry(:key, :value)
          in (envelope is Map ? envelope : json).entries)
        key.toString(): value,
    };

    String? pick(List<String> keys) {
      for (final key in keys) {
        final value = map[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
      return null;
    }

    String? name(List<String> keys) {
      final value = pick(keys);
      if (value == null) return null;
      if (RegExp(r'[\u0000-\u001F\u007F]').hasMatch(value)) {
        throw ConfigException(
          'Branding "${keys.first}" contains control characters.',
        );
      }
      if (value.length > 255) {
        throw ConfigException(
          'Branding "${keys.first}" is longer than 255 characters.',
        );
      }
      return value;
    }

    String? url(List<String> keys) {
      final value = pick(keys);
      if (value == null) return null;
      final uri = Uri.tryParse(value);
      final local = uri?.host == 'localhost' || uri?.host == '127.0.0.1';
      if (uri == null ||
          uri.host.isEmpty ||
          !(uri.isScheme('https') || (uri.isScheme('http') && local))) {
        throw ConfigException(
          'Branding "${keys.first}" must be an https URL, got "$value".',
        );
      }
      return value;
    }

    String? color(List<String> keys) {
      final value = pick(keys);
      if (value == null) return null;
      if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
        throw ConfigException(
          'Branding "${keys.first}" must be a colour like "#1e40af", '
          'got "$value".',
        );
      }
      return value.toUpperCase();
    }

    return InstitutionBranding(
      tenantId: tenantId,
      appName: name(['app_name', 'institution_name', 'name']),
      logoUrl: url(['logo_url', 'logo']),
      launcherIconUrl: url(['launcher_icon_url', 'icon_url', 'favicon_url']),
      primaryColor: color(['primary_color']),
      secondaryColor: color(['secondary_color']),
      appCode: pick(['app_code', 'institution_id', 'tenant_id']),
    );
  }

  /// Fetches the branding of the school served from [host].
  static Future<InstitutionBranding> fetch(
    Uri host, {
    String path = '/api/v1/branding',
    RemoteFetch? fetch,
  }) async {
    if (!host.isScheme('https') &&
        !(host.isScheme('http') &&
            (host.host == 'localhost' || host.host == '127.0.0.1'))) {
      throw ConfigException('The school host must be https, got "$host".');
    }
    final url = host.replace(path: path);
    final Uint8List bytes;
    try {
      bytes = await (fetch ?? httpGet)(url, maxBytes: maxBrandingBytes);
    } on ConfigException {
      rethrow;
    } on Object catch (e) {
      throw ConfigException('Could not fetch branding from $url: $e');
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (e) {
      throw ConfigException('$url did not return JSON: ${e.message}');
    }
    return InstitutionBranding.parse(json, tenantId: host.host);
  }

  Map<String, Object?> toJson() => {
    'tenant_id': tenantId,
    'slug': slug,
    'app_name': appName,
    'logo_url': logoUrl,
    'launcher_icon_url': launcherIconUrl,
    'primary_color': primaryColor,
    'secondary_color': secondaryColor,
    'app_code': appCode,
  }..removeWhere((_, value) => value == null);

  @override
  String toString() => 'InstitutionBranding($tenantId: $appName)';
}
