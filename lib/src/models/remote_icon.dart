import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../config/app_identity.dart';
import '../exceptions.dart';

/// An icon published by a server, with optional artwork per appearance.
///
/// What happens with it depends on the platform:
///
/// * **macOS, Windows, Linux**: the image is downloaded and applied as the
///   Dock/taskbar/window icon; [dark] is used while the system is in dark
///   mode.
/// * **Web**: the URL becomes the favicon (no download needed).
/// * **iOS, Android**: launcher icons must be compiled into the app; neither
///   OS accepts a downloaded image. If [variant] names a variant shipped in
///   this build, IconShift switches to it instead (the OS then applies its
///   dark/tinted/clear artwork itself). Ship server icons in the build with
///   `remote:` in icon_shift.yaml (`icon_shift_cli generate`).
///
/// The JSON form a server returns (relative URLs resolve against the URL the
/// JSON was fetched from):
///
/// ```json
/// {
///   "id": "halloween_2026",
///   "variant": "halloween",
///   "name": "Spooky Notes",
///   "icon": "https://cdn.example.com/icons/halloween.png",
///   "appearances": {
///     "dark": "halloween_dark.png",
///     "tinted": "halloween_tinted.png",
///     "clear": "halloween_clear.png"
///   }
/// }
/// ```
@immutable
class RemoteIcon {
  const RemoteIcon({
    required this.url,
    this.id,
    this.dark,
    this.tinted,
    this.clear,
    this.variant,
    this.name,
  });

  /// Parses the JSON form above. Throws [InvalidArgumentException] when it
  /// is malformed or a URL is not `https` (plain `http` is accepted only for
  /// `localhost`, for development).
  factory RemoteIcon.fromJson(Map<String, Object?> json, {Uri? baseUri}) {
    Uri? url(Object? value, String where) {
      if (value == null) return null;
      if (value is! String || value.trim().isEmpty) {
        throw InvalidArgumentException('"$where" must be a URL string.');
      }
      final parsed = Uri.tryParse(value.trim());
      if (parsed == null) {
        throw InvalidArgumentException('"$where" is not a valid URL: $value');
      }
      return checkRemoteIconUrl(baseUri?.resolveUri(parsed) ?? parsed, where);
    }

    String? string(Object? value, String where) {
      if (value == null) return null;
      if (value is! String || value.trim().isEmpty) {
        throw InvalidArgumentException('"$where" must be a non-empty string.');
      }
      return value;
    }

    final appearances = json['appearances'];
    if (appearances != null && appearances is! Map) {
      throw const InvalidArgumentException('"appearances" must be an object.');
    }
    final a = (appearances as Map?) ?? const {};
    final icon = url(json['icon'], 'icon');
    if (icon == null) {
      throw const InvalidArgumentException('A remote icon needs "icon".');
    }
    return RemoteIcon(
      url: icon,
      id: string(json['id'], 'id'),
      dark: url(a['dark'], 'appearances.dark'),
      tinted: url(a['tinted'], 'appearances.tinted'),
      clear: url(a['clear'], 'appearances.clear'),
      variant: string(json['variant'], 'variant'),
      name: string(json['name'], 'name'),
    );
  }

  /// Parses [source] as JSON (see [RemoteIcon.fromJson]).
  factory RemoteIcon.decode(String source, {Uri? baseUri}) {
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException catch (e) {
      throw InvalidArgumentException(
        'Remote icon JSON is invalid: ${e.message}',
      );
    }
    if (json is! Map<String, Object?>) {
      throw const InvalidArgumentException(
        'Remote icon JSON must be an object.',
      );
    }
    return RemoteIcon.fromJson(json, baseUri: baseUri);
  }

  /// The regular (light) artwork.
  final Uri url;

  /// Stable identifier chosen by the server; defaults to [url].
  final String? id;

  final Uri? dark;
  final Uri? tinted;
  final Uri? clear;

  /// Variant compiled into the app to use where downloaded images cannot be
  /// applied (iOS, Android).
  final String? variant;

  /// Display name to apply with the icon, where the platform allows it.
  final String? name;

  /// Identifier used in the saved selection and native state.
  String get key => id ?? url.toString();

  /// The artwork for [mode], falling back to [url].
  Uri urlFor(IconAppearanceMode mode) =>
      switch (mode) {
        IconAppearanceMode.light => null,
        IconAppearanceMode.dark => dark,
        IconAppearanceMode.tinted => tinted,
        IconAppearanceMode.clear => clear,
      } ??
      url;

  Map<String, Object?> toJson() => {
    'icon': url.toString(),
    'id': ?id,
    'variant': ?variant,
    'name': ?name,
    if (dark != null || tinted != null || clear != null)
      'appearances': {
        if (dark != null) 'dark': dark.toString(),
        if (tinted != null) 'tinted': tinted.toString(),
        if (clear != null) 'clear': clear.toString(),
      },
  };

  @override
  bool operator ==(Object other) =>
      other is RemoteIcon &&
      other.url == url &&
      other.id == id &&
      other.dark == dark &&
      other.tinted == tinted &&
      other.clear == clear &&
      other.variant == variant &&
      other.name == name;

  @override
  int get hashCode => Object.hash(url, id, dark, tinted, clear, variant, name);

  @override
  String toString() => 'RemoteIcon($key)';
}

/// Throws [InvalidArgumentException] unless [url] is `https` (or `http` to
/// `localhost` / `127.0.0.1`, for development).
Uri checkRemoteIconUrl(Uri url, [String where = 'url']) {
  final local = url.host == 'localhost' || url.host == '127.0.0.1';
  if (!(url.isScheme('https') || (url.isScheme('http') && local)) ||
      url.host.isEmpty) {
    throw InvalidArgumentException(
      '"$where" must be an https URL, got "$url".',
    );
  }
  return url;
}

/// Largest image IconShift downloads for a remote icon.
const int maxRemoteIconBytes = 5 * 1024 * 1024;

/// Whether [bytes] start like a PNG, JPEG, GIF, BMP, WebP or ICO file.
bool looksLikeImage(Uint8List bytes) {
  bool starts(List<int> magic, [int offset = 0]) {
    if (bytes.length < offset + magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[offset + i] != magic[i]) return false;
    }
    return true;
  }

  return starts(const [0x89, 0x50, 0x4E, 0x47]) || // PNG
      starts(const [0xFF, 0xD8, 0xFF]) || // JPEG
      starts(const [0x47, 0x49, 0x46, 0x38]) || // GIF
      starts(const [0x42, 0x4D]) || // BMP
      starts(const [0x00, 0x00, 0x01, 0x00]) || // ICO
      (starts(const [0x52, 0x49, 0x46, 0x46]) &&
          starts(const [0x57, 0x45, 0x42, 0x50], 8)); // WebP
}
