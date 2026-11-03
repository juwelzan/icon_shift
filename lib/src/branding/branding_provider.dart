import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../engine.dart' show RemoteFetcher;
import '../models/remote_icon.dart' show checkRemoteIconUrl;
import '../platform/http_fetch.dart';
import 'branding_profile.dart';

/// Where the branding of one tenant comes from.
///
/// IconShift does not know any particular back end: implement this, or use
/// [HttpBrandingProvider] for a JSON endpoint and
/// [CallbackBrandingProvider] to wrap code you already have.
///
/// ```dart
/// class MyApiBranding extends BrandingProvider {
///   MyApiBranding(this.institution);
///   final Institution institution;
///
///   @override
///   String get tenantId => institution.id;
///
///   @override
///   Future<BrandingProfile> fetch() async {
///     final json = await api.getBranding(institution.id);
///     return BrandingProfile.parse(json, tenantId: tenantId);
///   }
/// }
/// ```
abstract class BrandingProvider {
  const BrandingProvider();

  /// Identifies the tenant. The cache is keyed by it, so branding of one
  /// tenant can never be shown for another.
  String get tenantId;

  /// Reads the branding. Throw to signal failure: the controller then keeps
  /// the cached or default branding instead of breaking the app.
  Future<BrandingProfile> fetch();
}

/// Reads branding from a JSON endpoint.
///
/// ```dart
/// // One endpoint per tenant (a host or path per tenant):
/// HttpBrandingProvider.host(
///   Uri.parse('https://abc.example.com'),
///   path: '/api/v1/branding',
/// );
///
/// // One endpoint for all tenants:
/// HttpBrandingProvider(
///   url: Uri.parse('https://api.example.com/branding?tenant=school_123'),
///   tenantId: 'school_123',
///   headers: {'Authorization': 'Bearer $token'},
/// );
/// ```
///
/// [fields] maps the response onto [BrandingProfile]; the defaults cover
/// common names, so most APIs need no mapping at all.
class HttpBrandingProvider extends BrandingProvider {
  HttpBrandingProvider({
    required Uri url,
    String? tenantId,
    this.headers = const {'Accept': 'application/json'},
    this.fields = const BrandingFieldMap(),
    this.maxBytes = 256 * 1024,
    this.strict = false,
    RemoteFetcher? download,
  }) : url = checkRemoteIconUrl(url, 'url'),
       tenantId = tenantId ?? url.host,
       _download = download ?? httpGetBytes;

  /// For APIs that give every tenant its own host, where the host
  /// identifies the tenant. [path] is the endpoint on that host.
  factory HttpBrandingProvider.host(
    Uri host, {
    required String path,
    String? tenantId,
    Map<String, String> headers = const {'Accept': 'application/json'},
    BrandingFieldMap fields = const BrandingFieldMap(),
    int maxBytes = 256 * 1024,
    bool strict = false,
    RemoteFetcher? download,
  }) => HttpBrandingProvider(
    url: host.replace(path: path),
    tenantId: tenantId ?? host.host,
    headers: headers,
    fields: fields,
    maxBytes: maxBytes,
    strict: strict,
    download: download,
  );

  /// The endpoint. Must be https (http only for `localhost`).
  final Uri url;

  @override
  final String tenantId;

  final Map<String, String> headers;
  final BrandingFieldMap fields;

  /// Largest response accepted, so a wrong URL cannot exhaust memory.
  final int maxBytes;

  /// Fail on a malformed field instead of dropping it.
  final bool strict;

  final RemoteFetcher _download;

  @override
  Future<BrandingProfile> fetch() async {
    final bytes = await _download(url, maxBytes: maxBytes, headers: headers);
    return BrandingProfile.decode(
      utf8.decode(bytes),
      tenantId: tenantId,
      fields: fields,
      strict: strict,
    );
  }

  @override
  String toString() => 'HttpBrandingProvider($tenantId → $url)';
}

/// Wraps a function, for branding that already comes from somewhere else —
/// an existing API client, a local file, a test.
class CallbackBrandingProvider extends BrandingProvider {
  const CallbackBrandingProvider({
    required this.tenantId,
    required Future<BrandingProfile> Function() fetch,
  }) : _fetch = fetch;

  @override
  final String tenantId;

  final Future<BrandingProfile> Function() _fetch;

  @override
  Future<BrandingProfile> fetch() => _fetch();

  @override
  String toString() => 'CallbackBrandingProvider($tenantId)';
}

/// Serves a fixed profile: app-local branding, or a default per tenant.
@immutable
class StaticBrandingProvider extends BrandingProvider {
  const StaticBrandingProvider(this.profile);

  final BrandingProfile profile;

  @override
  String get tenantId => profile.tenantId;

  @override
  Future<BrandingProfile> fetch() async => profile;

  @override
  String toString() => 'StaticBrandingProvider(${profile.tenantId})';
}
