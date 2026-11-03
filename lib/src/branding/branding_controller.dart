import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../engine.dart';
import '../models/remote_icon.dart';
import '../models/result.dart';
import '../platform/http_fetch.dart';
import 'branding_profile.dart';

/// Fetches the raw branding document for [tenant]. Throw to signal failure;
/// the controller then keeps the cached or default branding.
typedef BrandingFetcher = Future<String> Function(BrandingTenant tenant);

/// One institution, and where its branding comes from.
///
/// DigiEdu / Schoolmate gives every school its own host, so the host *is* the
/// tenant: `https://amena-baki.digiedu.online` →
/// `GET https://amena-baki.digiedu.online/api/v1/branding` (public, no login).
@immutable
class BrandingTenant {
  /// A tenant served from [host]. [id] defaults to the host, which is what
  /// keeps one school's cache out of another's.
  BrandingTenant({
    required Uri host,
    String? id,
    String path = '/api/v1/branding',
  }) : this.endpoint(
         url: checkRemoteIconUrl(host.replace(path: path), 'host'),
         id: id ?? host.host,
       );

  /// A tenant whose branding lives at an arbitrary [url].
  const BrandingTenant.endpoint({required this.url, required this.id});

  /// Stable identifier; the cache is keyed by it.
  final String id;

  /// Where the branding document is fetched from.
  final Uri url;

  @override
  bool operator ==(Object other) =>
      other is BrandingTenant && other.id == id && other.url == url;

  @override
  int get hashCode => Object.hash(id, url);

  @override
  String toString() => 'BrandingTenant($id → $url)';
}

/// What happened on the last [BrandingController.load].
enum BrandingStatus {
  /// Nothing has been loaded yet.
  idle,

  /// Shown from the cache while the server is being asked.
  cached,

  /// Fresh from the server.
  live,

  /// The server could not be reached; cached or default branding is shown.
  offline,

  /// The server answered with something unusable; the previous branding
  /// stays.
  invalid,
}

/// The branding currently in effect, and where it came from.
@immutable
class BrandingState {
  const BrandingState({
    required this.profile,
    required this.status,
    this.tenant,
    this.error,
  });

  /// Never null: the default branding until a server answers.
  final BrandingProfile profile;
  final BrandingStatus status;
  final BrandingTenant? tenant;

  /// Why the last refresh failed, if it did.
  final String? error;

  bool get isDefault => tenant == null;

  @override
  bool operator ==(Object other) =>
      other is BrandingState &&
      other.profile == profile &&
      other.status == status &&
      other.tenant == tenant &&
      other.error == error;

  @override
  int get hashCode => Object.hash(profile, status, tenant, error);

  @override
  String toString() =>
      'BrandingState(${status.name}: $profile${error == null ? '' : ' — $error'})';
}

/// Server-driven, multi-tenant branding: one app, one branded experience per
/// institution.
///
/// ```dart
/// await IconShift.initialize(config);
/// final branding = IconShift.branding;
///
/// // After the user picks a school (its host identifies it):
/// await branding.load(BrandingTenant(host: Uri.parse('https://abc.digiedu.online')));
///
/// // In the UI:
/// ValueListenableBuilder<BrandingState>(
///   valueListenable: branding,
///   builder: (context, state, _) => Text(state.profile.displayName ?? 'Schoolmate'),
/// );
///
/// await branding.clear();           // logout
/// ```
///
/// [load] returns the cached branding immediately and refreshes in the
/// background, so startup never waits for the network. The cache holds only
/// the active institution, so switching schools cannot leak branding.
///
/// Changing the **launcher** name and icon is a separate, native-limited
/// step: see [applyLauncherBranding].
class BrandingController extends ChangeNotifier
    implements ValueListenable<BrandingState> {
  BrandingController({
    required IconShiftEngine engine,
    BrandingProfile? defaultBranding,
    BrandingFetcher? fetch,
    RemoteFetcher? download,
    this.timeout = const Duration(seconds: 10),
  }) : _engine = engine,
       _default =
           defaultBranding ?? const BrandingProfile(tenantId: _defaultTenant),
       _fetch = fetch,
       _download = download {
    _state = BrandingState(profile: _default, status: BrandingStatus.idle);
  }

  static const _defaultTenant = 'default';

  /// Largest branding document accepted from a server.
  static const int maxDocumentBytes = 256 * 1024;

  final IconShiftEngine _engine;
  final BrandingProfile _default;
  final BrandingFetcher? _fetch;
  final RemoteFetcher? _download;
  final Duration timeout;

  late BrandingState _state;
  BrandingTenant? _tenant;
  Future<void>? _inFlight;

  @override
  BrandingState get value => _state;

  /// The branding in effect, falling back to the app's own.
  BrandingProfile get profile => _state.profile;

  /// The institution whose branding is shown, or `null` for the default.
  BrandingTenant? get tenant => _tenant;

  /// The branding the app ships with, used when no institution is selected
  /// and when a server has never answered.
  BrandingProfile get defaultBranding => _default;

  /// Shows [tenant]'s branding: the cached copy at once (so the first frame
  /// is already branded and offline start works), then the server's.
  ///
  /// Switching to a different institution drops the previous one's cache
  /// first, so nothing of it can be shown. Returns when the refresh is done;
  /// ignore the future to let it finish in the background.
  ///
  /// [refresh] re-fetches even when the cached branding is current.
  Future<BrandingState> load(
    BrandingTenant tenant, {
    bool refresh = false,
  }) async {
    final switching = _tenant != null && _tenant!.id != tenant.id;
    if (switching) await _engine.clearBranding();
    _tenant = tenant;

    if (!switching || !refresh) {
      final cached = _readCache(tenant);
      if (cached != null) {
        _emit(
          BrandingState(
            profile: cached,
            status: BrandingStatus.cached,
            tenant: tenant,
          ),
        );
      } else if (switching) {
        // Never keep the previous school's branding on screen.
        _emit(
          BrandingState(
            profile: _default,
            status: BrandingStatus.idle,
            tenant: tenant,
          ),
        );
      }
    }

    // One refresh at a time, so a rebuild storm cannot hammer the server.
    final pending = _inFlight;
    if (pending != null) {
      await pending;
      return _state;
    }
    final run = _refresh(tenant);
    _inFlight = run;
    try {
      await run;
    } finally {
      _inFlight = null;
    }
    return _state;
  }

  /// Re-fetches the active institution's branding.
  Future<BrandingState> refresh() async {
    final tenant = _tenant;
    if (tenant == null) return _state;
    return load(tenant, refresh: true);
  }

  /// Forgets the institution and its cache, and goes back to the app's own
  /// branding. Call it on logout and before another school signs in.
  Future<void> clear() async {
    _tenant = null;
    await _engine.clearBranding();
    _emit(BrandingState(profile: _default, status: BrandingStatus.idle));
  }

  /// Applies the active branding to the **launcher** where the platform
  /// allows it: the name and icon of a home-screen shortcut on Android, the
  /// Dock icon and window title on desktop, the favicon and tab title on
  /// web. iOS can only switch between icons compiled into the build.
  ///
  /// The downloaded image is used only when the platform accepts arbitrary
  /// images; [fallbackVariant] names a variant from the build for the rest.
  /// Read the returned [IconShiftResult] — it says exactly what the OS did.
  Future<IconShiftResult> applyLauncherBranding({
    String? fallbackVariant,
  }) async {
    final profile = _state.profile;
    final icon = profile.launcherIconUrl;
    return _engine.setArbitraryIdentity(
      name: profile.displayName,
      variant: fallbackVariant,
      remoteIcon: icon == null
          ? null
          : RemoteIcon(
              url: icon,
              id: '${profile.tenantId}@${profile.version}',
              variant: fallbackVariant,
            ),
    );
  }

  /// Downloads the institution's logo for in-app use, or `null` when there
  /// is none or it cannot be fetched. Images over [maxRemoteIconBytes] and
  /// anything that is not an image are refused.
  Future<Uint8List?> loadLogo() async {
    final url = _state.profile.logoUrl;
    if (url == null) return null;
    try {
      final bytes = await (_download ?? httpGetBytes)(
        url,
        maxBytes: maxRemoteIconBytes,
      );
      if (!looksLikeImage(bytes)) {
        debugPrint('IconShift: branding logo at $url is not an image.');
        return null;
      }
      return bytes;
    } on Object catch (e) {
      debugPrint('IconShift: could not load the branding logo: $e');
      return null;
    }
  }

  Future<void> _refresh(BrandingTenant tenant) async {
    final String document;
    try {
      document = await (_fetch ?? _httpFetch)(tenant).timeout(timeout);
    } on Object catch (e) {
      // Offline is not an error the app should notice: keep showing what we
      // have, cached or default.
      _emit(
        BrandingState(
          profile: _state.tenant?.id == tenant.id
              ? _state.profile
              : _readCache(tenant) ?? _default,
          status: BrandingStatus.offline,
          tenant: tenant,
          error: '$e',
        ),
      );
      return;
    }
    if (tenant.id != _tenant?.id) return; // Switched again while fetching.

    final BrandingProfile fresh;
    try {
      fresh = BrandingProfile.decode(document, tenantId: tenant.id);
    } on Object catch (e) {
      _emit(
        BrandingState(
          profile: _state.profile,
          status: BrandingStatus.invalid,
          tenant: tenant,
          error: '$e',
        ),
      );
      return;
    }

    // Unchanged branding: no cache write, no listener notification.
    final current = _state.profile;
    if (_state.status != BrandingStatus.live ||
        current.tenantId != fresh.tenantId ||
        current.version != fresh.version) {
      await _engine.writeBranding(tenant.id, jsonEncode(fresh.toJson()));
    }
    _emit(
      BrandingState(
        profile: fresh,
        status: BrandingStatus.live,
        tenant: tenant,
      ),
    );
  }

  Future<String> _httpFetch(BrandingTenant tenant) async {
    final bytes = await (_download ?? httpGetBytes)(
      tenant.url,
      maxBytes: maxDocumentBytes,
      // Laravel answers HTML/redirects for errors without it.
      headers: const {'Accept': 'application/json'},
    );
    return utf8.decode(bytes);
  }

  BrandingProfile? _readCache(BrandingTenant tenant) {
    final json = _engine.readBranding(tenant.id);
    if (json == null) return null;
    try {
      final cached = BrandingProfile.decode(json, tenantId: tenant.id);
      final owner = cached.extras[cachedForTenantKey];
      if (owner != null && owner != tenant.id) {
        debugPrint('IconShift: cached branding belongs to "$owner"; ignored.');
        return null;
      }
      return cached;
    } on Object catch (e) {
      debugPrint('IconShift: cached branding is unusable ($e).');
      return null;
    }
  }

  void _emit(BrandingState state) {
    if (state == _state) return;
    _state = state;
    notifyListeners();
  }
}
