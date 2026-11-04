import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../engine.dart';
import '../models/launcher_name.dart';
import '../models/remote_icon.dart';
import '../models/result.dart';
import '../exceptions.dart';
import '../platform/http_fetch.dart';
import 'branding_profile.dart';
import 'branding_provider.dart';

/// How far native (launcher) branding got on this platform.
enum NativeBrandingScope {
  /// The app's own launcher entry now shows the tenant's name (and icon).
  applied,

  /// The OS only shows values compiled into the app and this tenant's are
  /// not: produce a build that contains them (`icon_shift_cli`).
  requiresBuild,

  /// This platform has no launcher identity IconShift can change.
  unsupported,
}

/// What applying branding to the launcher actually achieved, so an app can
/// tell the difference between "done" and "needs a branded build".
@immutable
class NativeBrandingReport {
  const NativeBrandingReport({
    required this.scope,
    required this.result,
    this.message,
  });

  final NativeBrandingScope scope;

  /// The outcome per property, with the OS's own wording.
  final IconShiftResult result;

  /// Why it ended there, when it is not [NativeBrandingScope.applied].
  final String? message;

  bool get isApplied => scope == NativeBrandingScope.applied;

  /// A branded build is the only way to get this tenant's launcher
  /// identity on this platform.
  bool get needsBuild => scope == NativeBrandingScope.requiresBuild;

  @override
  String toString() =>
      'NativeBrandingReport(${scope.name}${message == null ? '' : ': $message'})';
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
    this.tenantId,
    this.error,
  });

  /// Never null: the default branding until a server answers.
  final BrandingProfile profile;
  final BrandingStatus status;

  /// The tenant whose branding this is, or `null` for the default.
  final String? tenantId;

  /// Why the last refresh failed, if it did.
  final String? error;

  bool get isDefault => tenantId == null;

  @override
  bool operator ==(Object other) =>
      other is BrandingState &&
      other.profile == profile &&
      other.status == status &&
      other.tenantId == tenantId &&
      other.error == error;

  @override
  int get hashCode => Object.hash(profile, status, tenantId, error);

  @override
  String toString() =>
      'BrandingState(${status.name}: $profile${error == null ? '' : ' — $error'})';
}

/// Server-driven, multi-tenant branding: one app, one branded experience per
/// tenant.
///
/// ```dart
/// await IconShift.initialize(config, defaultBranding: appBranding);
///
/// // After the user picks a tenant:
/// await IconShift.loadBranding(
///   HttpBrandingProvider.host(
///     Uri.parse('https://abc.example.com'),
///     path: '/api/v1/branding',
///   ),
/// );
///
/// // In the UI:
/// ValueListenableBuilder<BrandingState>(
///   valueListenable: IconShift.branding,
///   builder: (context, state, _) => Text(state.profile.displayName ?? 'My App'),
/// );
///
/// await IconShift.branding.clear();   // logout
/// ```
///
/// [load] returns the cached branding immediately and refreshes in the
/// background, so startup never waits for the network. The cache holds only
/// the active tenant, so switching tenants cannot leak branding.
///
/// Changing the **launcher** name and icon is a separate, native-limited
/// step: see [applyLauncherBranding].
class BrandingController extends ChangeNotifier
    implements ValueListenable<BrandingState> {
  BrandingController({
    required IconShiftEngine engine,
    BrandingProfile? defaultBranding,
    RemoteFetcher? download,
    this.timeout = const Duration(seconds: 10),
  }) : _engine = engine,
       _default =
           defaultBranding ?? const BrandingProfile(tenantId: _defaultTenant),
       _download = download {
    _state = BrandingState(profile: _default, status: BrandingStatus.idle);
  }

  static const _defaultTenant = 'default';

  final IconShiftEngine _engine;
  final BrandingProfile _default;
  final RemoteFetcher? _download;
  final Duration timeout;

  late BrandingState _state;
  BrandingProvider? _provider;
  Future<void>? _inFlight;

  @override
  BrandingState get value => _state;

  /// The branding in effect, falling back to the app's own.
  BrandingProfile get profile => _state.profile;

  /// Where the active branding comes from, or `null` for the default.
  BrandingProvider? get provider => _provider;

  /// The tenant whose branding is shown, or `null` for the default.
  String? get tenantId => _provider?.tenantId;

  /// The branding the app ships with, used when no tenant is selected and
  /// when a provider has never answered.
  BrandingProfile get defaultBranding => _default;

  /// Shows the branding [provider] serves: the cached copy at once (so the
  /// first frame is already branded and offline start works), then the
  /// provider's.
  ///
  /// Switching to a different tenant drops the previous one's cache first,
  /// so nothing of it can be shown. Returns when the refresh is done; ignore
  /// the future to let it finish in the background.
  ///
  /// [refresh] re-fetches even when the cached branding is current.
  Future<BrandingState> load(
    BrandingProvider provider, {
    bool refresh = false,
  }) async {
    final tenantId = provider.tenantId;
    final switching = _provider != null && _provider!.tenantId != tenantId;
    if (switching) await _engine.clearBranding();
    _provider = provider;

    if (!switching || !refresh) {
      final cached = _readCache(tenantId);
      if (cached != null) {
        _emit(
          BrandingState(
            profile: cached,
            status: BrandingStatus.cached,
            tenantId: tenantId,
          ),
        );
      } else if (switching) {
        // Never keep the previous tenant's branding on screen.
        _emit(
          BrandingState(
            profile: _default,
            status: BrandingStatus.idle,
            tenantId: tenantId,
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
    final run = _refresh(provider);
    _inFlight = run;
    try {
      await run;
    } finally {
      _inFlight = null;
    }
    return _state;
  }

  /// Re-fetches the active tenant's branding.
  Future<BrandingState> refresh() async {
    final provider = _provider;
    if (provider == null) return _state;
    return load(provider, refresh: true);
  }

  /// Shows [profile] directly and caches it, without a provider — for
  /// branding the app already has (a push payload, a bundled file, a test).
  Future<BrandingState> apply(BrandingProfile profile) async {
    final current = _provider?.tenantId;
    if (current != null && current != profile.tenantId) {
      await _engine.clearBranding();
    }
    _provider = StaticBrandingProvider(profile);
    await _engine.writeBranding(profile.tenantId, jsonEncode(profile.toJson()));
    _emit(
      BrandingState(
        profile: profile,
        status: BrandingStatus.live,
        tenantId: profile.tenantId,
      ),
    );
    return _state;
  }

  /// Forgets the tenant and its cache, and goes back to the app's own
  /// branding. Call it on logout and before another tenant signs in.
  Future<void> clear() async {
    _provider = null;
    await _engine.clearBranding();
    _emit(BrandingState(profile: _default, status: BrandingStatus.idle));
  }

  /// Applies the active branding to the app's **own launcher entry** as far
  /// as the platform allows, and reports how far that was. Nothing else is
  /// created — no widget, shortcut or second icon.
  ///
  /// | Platform | Result |
  /// | --- | --- |
  /// | Android | the launcher entry switches to the variant whose compiled-in name matches; otherwise `requiresBuild` |
  /// | iOS | the icon of [fallbackVariant] if the build has it; the name needs a build |
  /// | macOS, Windows, Linux | Dock/taskbar icon and window title |
  /// | Web | favicon and tab title |
  Future<NativeBrandingReport> applyLauncherBranding({
    String? fallbackVariant,
  }) async {
    final profile = _state.profile;
    final name = profile.displayName;
    final capabilities = await _engine.getCapabilities();

    if (capabilities.iconAndNameLinked && name != null) {
      final launcher = await _engine.changeLauncherName(name);
      return NativeBrandingReport(
        scope: switch (launcher.status) {
          IconShiftStatus.success ||
          IconShiftStatus.pending => NativeBrandingScope.applied,
          IconShiftStatus.requiresPreconfiguredLauncher ||
          IconShiftStatus.requiresNewBuild => NativeBrandingScope.requiresBuild,
          _ => NativeBrandingScope.unsupported,
        },
        result:
            launcher.details ??
            IconShiftResult(
              icon: const OperationOutcome.notRequested(),
              displayName: OperationOutcome(
                launcher.success
                    ? OperationStatus.unchanged
                    : OperationStatus.unsupported,
                message: launcher.message,
              ),
              operation: IconShiftOperation.setDisplayName,
              platform: launcher.platform,
            ),
        message: launcher.message,
      );
    }

    final icon = profile.launcherIconUrl;
    final result = await _engine.setArbitraryIdentity(
      name: name,
      variant: fallbackVariant,
      remoteIcon: icon == null
          ? null
          : RemoteIcon(
              url: icon,
              id: '${profile.tenantId}@${profile.version}',
              variant: fallbackVariant,
            ),
    );

    final wanted = [
      if (name != null) result.displayName,
      if (icon != null || fallbackVariant != null) result.icon,
    ];
    final blocked = wanted.where(
      (o) =>
          o.status == OperationStatus.unsupported ||
          o.status == OperationStatus.failed,
    );
    final NativeBrandingScope scope;
    String? message;
    if (wanted.isEmpty) {
      scope = NativeBrandingScope.unsupported;
      message = 'The branding carries neither a name nor an icon.';
    } else if (blocked.isEmpty) {
      scope = NativeBrandingScope.applied;
    } else if (blocked.any(
      (o) => o.errorCode == IconShiftErrorCode.buildRequired,
    )) {
      scope = NativeBrandingScope.requiresBuild;
      message =
          'This platform only shows a launcher name compiled into the app. '
          'Build this tenant its own app: `dart run icon_shift_cli brand` '
          'with the tenant\'s branding.';
    } else {
      scope = NativeBrandingScope.unsupported;
      message = blocked.first.message;
    }
    return NativeBrandingReport(scope: scope, result: result, message: message);
  }

  /// Downloads the tenant's logo for in-app use, or `null` when there is
  /// none or it cannot be fetched. Images over [maxRemoteIconBytes] and
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

  Future<void> _refresh(BrandingProvider provider) async {
    final tenantId = provider.tenantId;
    final BrandingProfile fresh;
    try {
      fresh = await provider.fetch().timeout(timeout);
    } on Object catch (e) {
      // Unreachable or unusable: keep showing what we have, cached or
      // default. The app is never broken by a branding server.
      _emit(
        BrandingState(
          profile: _state.tenantId == tenantId
              ? _state.profile
              : _readCache(tenantId) ?? _default,
          // A malformed answer is the server's fault, not the network's.
          status: e is InvalidArgumentException
              ? BrandingStatus.invalid
              : BrandingStatus.offline,
          tenantId: tenantId,
          error: '$e',
        ),
      );
      return;
    }
    if (tenantId != _provider?.tenantId) return; // Switched while fetching.

    // Unchanged branding: no cache write, no listener notification.
    final current = _state.profile;
    if (_state.status != BrandingStatus.live ||
        current.tenantId != fresh.tenantId ||
        current.version != fresh.version) {
      await _engine.writeBranding(tenantId, jsonEncode(fresh.toJson()));
    }
    _emit(
      BrandingState(
        profile: fresh,
        status: BrandingStatus.live,
        tenantId: tenantId,
      ),
    );
  }

  BrandingProfile? _readCache(String tenantId) {
    final json = _engine.readBranding(tenantId);
    if (json == null) return null;
    try {
      final cached = BrandingProfile.decode(json, tenantId: tenantId);
      final owner = cached.extras[cachedForTenantKey];
      if (owner != null && owner != tenantId) {
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
