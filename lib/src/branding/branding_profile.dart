import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../exceptions.dart';
import '../models/remote_icon.dart' show checkRemoteIconUrl;
import '../validation/config_validator.dart' show displayNameProblem;

/// Which keys of a branding response map onto [BrandingProfile].
///
/// The defaults accept the names most back ends use, so a typical JSON API
/// needs no mapping. Give your own lists when the field names differ:
///
/// ```dart
/// const BrandingFieldMap(
///   envelope: 'result',
///   appName: ['title'],
///   launcherIconUrl: ['icon'],
/// );
/// ```
///
/// Each list is tried in order; the first non-empty string wins.
@immutable
class BrandingFieldMap {
  const BrandingFieldMap({
    this.envelope = 'data',
    this.appName = const ['app_name', 'name'],
    this.institutionName = const ['institution_name'],
    this.logoUrl = const ['logo_url', 'logo'],
    this.launcherIconUrl = const [
      'launcher_icon_url',
      'icon_url',
      'favicon_url',
    ],
    this.primaryColor = const ['primary_color'],
    this.secondaryColor = const ['secondary_color'],
    this.code = const ['app_code', 'institution_id', 'tenant_id'],
    this.version = const ['branding_version', 'version'],
  });

  /// Key holding the payload when the API wraps it, e.g. `{"data": {…}}`.
  /// A response without it is read directly. Pass `null` for no envelope.
  final String? envelope;

  final List<String> appName;
  final List<String> institutionName;
  final List<String> logoUrl;

  /// Keys that may carry an image meant for the launcher icon or favicon.
  final List<String> launcherIconUrl;

  final List<String> primaryColor;
  final List<String> secondaryColor;

  /// Short code or id the server assigns to the tenant.
  final List<String> code;

  /// Server-side branding version, when it sends one.
  final List<String> version;

  /// Every key this map claims; the rest lands in [BrandingProfile.extras].
  Set<String> get knownKeys => {
    ...appName,
    ...institutionName,
    ...logoUrl,
    ...launcherIconUrl,
    ...primaryColor,
    ...secondaryColor,
    ...code,
    ...version,
  };
}

/// The branding one tenant publishes: the name, logo and colours the app
/// shows while that tenant is selected.
///
/// Parsed from whatever a [BrandingProvider] returns. A typical response:
///
/// ```json
/// {
///   "data": {
///     "app_name": "ABC School",
///     "logo_url": "https://cdn.example.com/abc/logo.png",
///     "launcher_icon_url": "https://cdn.example.com/abc/icon.png",
///     "primary_color": "#2563EB",
///     "secondary_color": "#4F46E5",
///     "institution_id": "school_123"
///   }
/// }
/// ```
///
/// [BrandingFieldMap] controls which keys are read, so no particular back
/// end is baked in. Every field is optional: a server that only sends a name
/// still produces a usable profile, and the rest falls back to the app's own
/// branding.
@immutable
class BrandingProfile {
  const BrandingProfile({
    required this.tenantId,
    this.appName,
    this.institutionName,
    this.logoUrl,
    this.launcherIconUrl,
    this.primaryColor,
    this.secondaryColor,
    this.appCode,
    this.version,
    this.extras = const {},
  });

  /// Which institution this belongs to. The cache is keyed by it, so two
  /// institutions can never read each other's branding.
  final String tenantId;

  /// Name for the app bar, launcher branding and window title.
  final String? appName;

  /// Full institution name, where it differs from [appName].
  final String? institutionName;

  /// In-app logo (https).
  final Uri? logoUrl;

  /// Image meant for the launcher icon / favicon (https).
  final Uri? launcherIconUrl;

  /// ARGB, e.g. `0xFF1E40AF`.
  final int? primaryColor;
  final int? secondaryColor;

  /// Short code the server assigns to the institution.
  final String? appCode;

  /// Changes whenever the branding changes. Taken from the server when it
  /// sends one, else computed from the content by [BrandingProfile.parse], so
  /// unchanged branding is never re-applied.
  final String? version;

  /// Fields this class does not model, kept so the app can read them.
  final Map<String, Object?> extras;

  /// The name to show, preferring [appName].
  String? get displayName => appName ?? institutionName;

  bool get isEmpty =>
      appName == null &&
      institutionName == null &&
      logoUrl == null &&
      launcherIconUrl == null &&
      primaryColor == null &&
      secondaryColor == null;

  /// Parses a server response for [tenantId].
  ///
  /// Malformed or hostile values are rejected rather than shown: a colour
  /// must be `#RGB`/`#RRGGBB`, a URL must be https (http only for
  /// `localhost`), and a name must be printable and at most 255 characters.
  /// [strict] throws [InvalidArgumentException] instead of dropping the bad
  /// field; the default keeps the rest of the branding usable.
  factory BrandingProfile.parse(
    Object? json, {
    required String tenantId,
    BrandingFieldMap fields = const BrandingFieldMap(),
    bool strict = false,
  }) {
    if (json is! Map) {
      throw const InvalidArgumentException(
        'A branding response must be a JSON object.',
      );
    }
    final envelope = fields.envelope == null ? null : json[fields.envelope];
    final map = <String, Object?>{
      for (final MapEntry(:key, :value)
          in (envelope is Map ? envelope : json).entries)
        key.toString(): value,
    };

    void reject(String field, String problem) {
      if (strict) {
        throw InvalidArgumentException('Branding "$field": $problem');
      }
      debugPrint('IconShift: ignoring branding "$field" ($problem).');
    }

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
      final problem = displayNameProblem(value);
      if (problem != null) {
        reject(keys.first, problem);
        return null;
      }
      return value;
    }

    Uri? url(List<String> keys) {
      final value = pick(keys);
      if (value == null) return null;
      final parsed = Uri.tryParse(value);
      if (parsed == null) {
        reject(keys.first, 'not a valid URL');
        return null;
      }
      try {
        return checkRemoteIconUrl(parsed, keys.first);
      } on InvalidArgumentException catch (e) {
        if (strict) rethrow;
        reject(keys.first, e.message);
        return null;
      }
    }

    int? color(List<String> keys) {
      final value = pick(keys);
      if (value == null) return null;
      final argb = parseHexColor(value);
      if (argb == null) {
        reject(keys.first, 'not a colour like "#1e40af"');
        return null;
      }
      return argb;
    }

    final known = fields.knownKeys;
    final profile = BrandingProfile(
      tenantId: tenantId,
      appName: name(fields.appName),
      institutionName: name(fields.institutionName),
      logoUrl: url(fields.logoUrl),
      // A favicon is the closest thing to a launcher icon when the server
      // sends no dedicated one.
      launcherIconUrl: url(fields.launcherIconUrl),
      primaryColor: color(fields.primaryColor),
      secondaryColor: color(fields.secondaryColor),
      appCode: pick(fields.code),
      version: pick(fields.version),
      extras: {
        for (final MapEntry(:key, :value) in map.entries)
          if (!known.contains(key)) key: value,
      },
    );
    // Many endpoints send neither a version nor an ETag, so derive one from
    // the content; unchanged branding is then never re-applied.
    return profile.version != null
        ? profile
        : profile.copyWith(version: contentVersion(profile));
  }

  /// Parses [source] as JSON (see [BrandingProfile.parse]).
  factory BrandingProfile.decode(
    String source, {
    required String tenantId,
    BrandingFieldMap fields = const BrandingFieldMap(),
    bool strict = false,
  }) {
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException catch (e) {
      throw InvalidArgumentException('Branding JSON is invalid: ${e.message}');
    }
    return BrandingProfile.parse(
      json,
      tenantId: tenantId,
      fields: fields,
      strict: strict,
    );
  }

  BrandingProfile copyWith({String? version}) => BrandingProfile(
    tenantId: tenantId,
    appName: appName,
    institutionName: institutionName,
    logoUrl: logoUrl,
    launcherIconUrl: launcherIconUrl,
    primaryColor: primaryColor,
    secondaryColor: secondaryColor,
    appCode: appCode,
    version: version ?? this.version,
    extras: extras,
  );

  /// The cached form. The tenant travels under [cachedForTenantKey] — not
  /// `tenant_id`, which servers use as an alias for [appCode] — so a cache
  /// written for one institution is never read as another's, and reparsing
  /// the cache yields an identical profile.
  Map<String, Object?> toJson() => {
    cachedForTenantKey: tenantId,
    'app_name': ?appName,
    'institution_name': ?institutionName,
    'logo_url': logoUrl?.toString(),
    'launcher_icon_url': launcherIconUrl?.toString(),
    'primary_color': primaryColor == null ? null : hexColor(primaryColor!),
    'secondary_color': secondaryColor == null
        ? null
        : hexColor(secondaryColor!),
    'app_code': ?appCode,
    'branding_version': ?version,
    if (extras.isNotEmpty) ...extras,
  }..removeWhere((_, value) => value == null);

  @override
  bool operator ==(Object other) =>
      other is BrandingProfile &&
      other.tenantId == tenantId &&
      other.appName == appName &&
      other.institutionName == institutionName &&
      other.logoUrl == logoUrl &&
      other.launcherIconUrl == launcherIconUrl &&
      other.primaryColor == primaryColor &&
      other.secondaryColor == secondaryColor &&
      other.appCode == appCode &&
      other.version == version;

  @override
  int get hashCode => Object.hash(
    tenantId,
    appName,
    institutionName,
    logoUrl,
    launcherIconUrl,
    primaryColor,
    secondaryColor,
    appCode,
    version,
  );

  @override
  String toString() =>
      'BrandingProfile($tenantId: ${displayName ?? '(no name)'}, '
      'version: $version)';
}

/// Key under which [BrandingProfile.toJson] records the owning tenant.
const String cachedForTenantKey = 'icon_shift_cached_for_tenant';

/// `#1e40af`, `#FFF` or `#FF1E40AF` → ARGB, or `null` when it is not a colour.
int? parseHexColor(String value) {
  final text = value.trim();
  if (!RegExp(
    r'^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$',
  ).hasMatch(text)) {
    return null;
  }
  var digits = text.substring(1);
  if (digits.length == 3) {
    digits = digits.split('').map((d) => '$d$d').join();
  }
  if (digits.length == 6) digits = 'FF$digits';
  return int.parse(digits, radix: 16);
}

/// ARGB → `#RRGGBB`, or `#AARRGGBB` when it is not fully opaque.
String hexColor(int argb) {
  final hex = argb.toRadixString(16).padLeft(8, '0').toUpperCase();
  return hex.startsWith('FF') ? '#${hex.substring(2)}' : '#$hex';
}

/// A stable version for branding the server did not version itself.
///
/// Two profiles with the same visible branding get the same value, so the app
/// can skip re-applying and re-downloading unchanged branding.
String contentVersion(BrandingProfile profile) {
  final content = [
    profile.appName,
    profile.institutionName,
    profile.logoUrl,
    profile.launcherIconUrl,
    profile.primaryColor,
    profile.secondaryColor,
    profile.appCode,
  ].join('\u0000');
  // FNV-1a over two 32-bit halves: no crypto dependency, and exact on web.
  var hi = 0xcbf29ce4, lo = 0x84222325;
  for (final byte in utf8.encode(content)) {
    lo ^= byte;
    final product = lo * 0x1b3;
    hi = (hi * 0x1b3 + (lo << 8) + product ~/ 0x100000000) & 0xffffffff;
    lo = product & 0xffffffff;
  }
  return 'c_${hi.toRadixString(16).padLeft(8, '0')}'
      '${lo.toRadixString(16).padLeft(8, '0')}';
}
