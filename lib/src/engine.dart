import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'config/app_identity.dart';
import 'config/icon_shift_config.dart';
import 'config/platform.dart';
import 'exceptions.dart';
import 'models/application_info.dart';
import 'models/capabilities.dart';
import 'models/diagnostics.dart';
import 'models/identity_properties.dart';
import 'models/identity_variant.dart';
import 'models/launcher_name.dart';
import 'models/preview.dart';
import 'models/remote_icon.dart';
import 'models/result.dart';
import 'models/state.dart';
import 'models/validation.dart';
import 'platform/http_fetch.dart';
import 'platform/icon_shift_platform_interface.dart';
import 'validation/config_validator.dart';

/// Downloads [url]; used for remote icons. Throws on any failure.
typedef RemoteFetcher =
    Future<Uint8List> Function(
      Uri url, {
      required int maxBytes,
      Map<String, String> headers,
    });

/// Selection keys persisted through [IconShiftPlatformInterface.saveSelection].
abstract final class _Keys {
  static const identity = 'identity';
  static const icon = 'icon';
  static const name = 'name';

  /// JSON of the applied [RemoteIcon].
  static const remote = 'remote';

  /// Cached [BrandingProfile] JSON of the active institution, and its
  /// tenant id. Only the active tenant is kept, so branding can never leak
  /// from one institution into another.
  static const branding = 'branding';

  /// The last name passed to [IconShiftEngine.changeLauncherName].
  static const launcherName = 'launcher_name';
  static const brandingTenant = 'branding_tenant';
}

/// Suffix of the native key while dark artwork is shown.
const _darkSuffix = '@dark';

/// Prefix of the native key of a remote icon.
const _remotePrefix = 'remote:';

/// Implements IconShift on top of an [IconShiftPlatformInterface].
///
/// [IconShift] is a static facade over one instance of this class; tests can
/// construct it directly with a fake platform.
class IconShiftEngine {
  IconShiftEngine({
    required this.platform,
    required this.targetPlatform,
    AssetBundle? assetBundle,
    this.locale,
    IconAppearanceMode Function()? systemAppearance,
    RemoteFetcher? fetch,
    ValueNotifier<String?>? displayNameNotifier,
  }) : displayName = displayNameNotifier ?? ValueNotifier(null),
       _assets = assetBundle ?? rootBundle,
       _systemAppearance = systemAppearance,
       _fetch = fetch ?? httpGetBytes;

  /// The name the app should show for itself right now: the saved custom
  /// name, else the name of the selected variant. Bind `MaterialApp.title`
  /// to it — on Android and web the framework writes that title into the
  /// recent-apps label / document title on every rebuild.
  final ValueNotifier<String?> displayName;

  final IconAppearanceMode Function()? _systemAppearance;
  final RemoteFetcher _fetch;

  /// Locale for [AppIdentity.localizedNames] (`de`, `pt_BR`), or `null` for
  /// the unlocalized names.
  final String? locale;

  final IconShiftPlatformInterface platform;

  /// The platform the app runs on, or `null` if IconShift does not support it.
  final IconShiftPlatform? targetPlatform;

  final AssetBundle _assets;

  IconShiftConfig? _config;
  late IconShiftCapabilities _capabilities;
  Map<String, String> _selection = {};
  IconShiftResult? _restoreResult;

  /// Serializes mutations so two switches never interleave natively.
  Future<void> _tail = Future.value();

  static const _defaultId = IconShiftConfig.defaultVariantId;

  bool get isInitialized => _config != null;

  ResolvedIdentity _resolve(String variantId) =>
      config.resolve(variantId, targetPlatform, locale: locale);

  IconShiftConfig get config =>
      _config ?? (throw const NotInitializedException());

  /// Result of re-applying the saved selection in [initialize], if any.
  IconShiftResult? get restoreResult => _restoreResult;

  Future<void> initialize(
    IconShiftConfig config, {
    bool restoreSelection = true,
  }) async {
    final validation = validateConfig(config);
    if (!validation.isValid) throw InvalidConfigurationException(validation);

    _capabilities = await _loadCapabilities();
    _selection = await _loadSelection();
    _config = config;
    await _recoverSelection();

    if (restoreSelection) _restoreResult = await _serialize(_restore);
    _publishDisplayName();

    if (kDebugMode) {
      final full = await validateConfiguration();
      for (final issue in full.issues) {
        if (issue.severity != ValidationSeverity.info) {
          debugPrint('IconShift: $issue');
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Mutations

  Future<IconShiftResult> setIdentity(String variantId) {
    _requireVariant(variantId);
    return _serialize(
      () => _setIdentity(variantId, IconShiftOperation.setIdentity),
    );
  }

  Future<IconShiftResult> setIcon(String variantId) {
    _requireVariant(variantId);
    // Linked platforms cannot change the icon without the name.
    if (_capabilities.iconAndNameLinked) return setIdentity(variantId);
    return _serialize(() async {
      final icon = await _applyIcon(variantId);
      await _commit(icon.outcome, {
        _Keys.identity: null,
        _Keys.icon: _storedIconKey(variantId),
        _Keys.remote: null,
      });
      return _result(
        IconShiftOperation.setIcon,
        icon.outcome,
        const OperationOutcome.notRequested(),
      );
    });
  }

  Future<IconShiftResult> setDisplayName(String name) {
    _requireInitialized();
    _requireValidName(name);
    return _serialize(() async {
      if (_capabilities.iconAndNameLinked) {
        // Android: the launcher shows the alias label, so switch to the
        // variant whose alias has this name and the current icon.
        final match = _linkedVariantFor(await _activeVariant(), name);
        if (match != null) {
          return _setIdentity(match, IconShiftOperation.setDisplayName);
        }
      }
      final outcome = _explainLinked(await _applyName(name), name);
      await _commit(outcome, {_Keys.identity: null, _Keys.name: name});
      return _result(
        IconShiftOperation.setDisplayName,
        const OperationOutcome.notRequested(),
        outcome,
      );
    });
  }

  Future<IconShiftResult> setCustomIdentity({
    String? iconVariant,
    String? displayName,
  }) {
    _requireInitialized();
    if (iconVariant == null && displayName == null) {
      throw const InvalidArgumentException(
        'setCustomIdentity needs an iconVariant, a displayName, or both.',
      );
    }
    if (iconVariant != null) _requireVariant(iconVariant);
    if (displayName != null) _requireValidName(displayName);

    return _serialize(() async {
      if (_capabilities.iconAndNameLinked && displayName != null) {
        final match = _linkedVariantFor(
          iconVariant ?? await _activeVariant(),
          displayName,
        );
        if (match != null) {
          return _setIdentity(match, IconShiftOperation.setCustomIdentity);
        }
      }
      var icon = const OperationOutcome.notRequested();
      String? linkedName;
      if (iconVariant != null) {
        final applied = await _applyIcon(iconVariant);
        icon = applied.outcome;
        linkedName = applied.linkedName;
        await _commit(icon, {
          _Keys.identity: null,
          _Keys.icon: _storedIconKey(iconVariant),
          _Keys.remote: null,
          if (_capabilities.iconAndNameLinked) _Keys.name: null,
        });
      }

      final OperationOutcome name;
      if (displayName == null) {
        name = _capabilities.iconAndNameLinked
            ? _linkedNameOutcome(icon, iconVariant!, linkedName)
            : const OperationOutcome.notRequested();
      } else if (icon.status == OperationStatus.failed) {
        name = _skippedAfterIconFailure;
      } else {
        name = _explainLinked(await _applyName(displayName), displayName);
        await _commit(name, {_Keys.identity: null, _Keys.name: displayName});
      }
      return _result(IconShiftOperation.setCustomIdentity, icon, name);
    });
  }

  /// Applies an icon published by a server; see [RemoteIcon] for what each
  /// platform does with it.
  Future<IconShiftResult> setRemoteIcon(RemoteIcon remote) {
    _requireInitialized();
    if (remote.name case final name?) _requireValidName(name);
    return _serialize(() async {
      if (!_capabilities.icon.acceptsArbitraryValues) {
        final variant = remote.variant == null
            ? null
            : config.migrateVariantId(remote.variant!);
        if (variant != null) {
          return _setIdentity(variant, IconShiftOperation.setRemoteIcon);
        }
        return _result(
          IconShiftOperation.setRemoteIcon,
          OperationOutcome.unsupported(
            remote.variant == null
                ? '${_platformName()} only shows launcher icons compiled into '
                      'the app; a downloaded image cannot be applied. Add the '
                      'icon at build time (remote: in icon_shift.yaml) and '
                      'send its variant id as "variant".'
                : 'Variant "${remote.variant}" is not part of this build, and '
                      '${_platformName()} cannot apply a downloaded image.',
            code: IconShiftErrorCode.buildRequired,
          ),
          const OperationOutcome.notRequested(),
        );
      }

      final icon = await _applyRemoteIcon(remote);
      await _commit(icon, {
        _Keys.identity: null,
        _Keys.icon: null,
        _Keys.remote: jsonEncode(remote.toJson()),
      });
      var name = const OperationOutcome.notRequested();
      if (remote.name case final remoteName?) {
        if (icon.status == OperationStatus.failed) {
          name = _skippedAfterIconFailure;
        } else {
          name = await _applyName(remoteName);
          await _commit(name, {_Keys.name: remoteName});
        }
      }
      return _result(IconShiftOperation.setRemoteIcon, icon, name);
    });
  }

  /// Applies [name] and an icon in the strongest way this platform allows,
  /// always on the app itself: arbitrary values on macOS, Windows, Linux
  /// and web; on Android the variant whose compiled-in name matches (see
  /// [changeLauncherName]); on iOS the icon of [variant] only — the name
  /// cannot change at runtime.
  Future<IconShiftResult> setArbitraryIdentity({
    String? variant,
    String? name,
    RemoteIcon? remoteIcon,
  }) async {
    _requireInitialized();
    if (variant != null) _requireVariant(variant);
    if (name != null) _requireValidName(name);

    if (remoteIcon != null) {
      final result = await setRemoteIcon(
        name == null ? remoteIcon : remoteIcon.withName(name),
      );
      if (name == null || result.displayName.isSuccessful) return result;
    }
    if (variant == null && name == null) {
      throw const InvalidArgumentException(
        'setArbitraryIdentity needs a name, a variant or a remoteIcon.',
      );
    }
    return setCustomIdentity(iconVariant: variant, displayName: name);
  }

  /// Changes the name the **installed** app's own launcher entry shows —
  /// home screen and app drawer — without a rebuild or reinstall, as far as
  /// the OS allows. The result is read back from the OS, not assumed.
  ///
  /// * **Android** — the launcher shows the label of the enabled
  ///   activity-alias. [name] is matched exactly against the labels compiled
  ///   into the APK (read from PackageManager); a match is enabled with
  ///   `PackageManager.setComponentEnabledSetting`, the new entry before the
  ///   old one is disabled. Android finishes a screen whose launcher entry
  ///   is disabled, so when the visible screen was opened through the entry
  ///   being replaced, the switch waits until the app leaves the foreground
  ///   ([IconShiftStatus.pending]) unless [immediate]. Any other name:
  ///   [IconShiftStatus.requiresPreconfiguredLauncher], nothing changed.
  /// * **iOS** — [IconShiftStatus.requiresNewBuild]: the Home Screen name is
  ///   `CFBundleDisplayName` of the signed bundle and no public API changes
  ///   it (asking for the name it already has is [IconShiftStatus.success]).
  /// * **macOS, Windows, Linux, web** — [IconShiftStatus.unsupported]; the
  ///   window / tab title is not touched.
  ///
  /// Nothing else is ever created — no widget, no shortcut, no second icon.
  Future<LauncherResult> changeLauncherName(
    String name, {
    bool immediate = false,
  }) async {
    _requireInitialized();
    _requireValidName(name);
    await _serialize(
      () => _saveSelection({..._selection, _Keys.launcherName: name}),
    );

    if (_capabilities.iconAndNameLinked) {
      return _switchLauncherEntry(
        LauncherProperty.name,
        name,
        immediate: immediate,
        pick: (identities, current) {
          final candidates = identities.where((i) => i.label == name);
          // Several aliases may share a label; keep the current icon if one
          // of them has it.
          final preferred = _linkedVariantFor(current, name);
          return candidates.where((i) => i.id == preferred).firstOrNull ??
              candidates.firstOrNull;
        },
        missing: (available) =>
            '"$name" is not one of the launcher names compiled into this app, '
            'so nothing was changed. Available: '
            '${available.map((n) => '"$n"').join(', ')}. Add "$name" as a '
            'variant in icon_shift.yaml and ship that build once.',
      );
    }

    final shown = await _appEntryName();
    if (targetPlatform == IconShiftPlatform.ios) {
      return shown == name
          ? _launcherResult(
              LauncherProperty.name,
              IconShiftStatus.success,
              name,
              applied: shown,
            )
          : _launcherResult(
              LauncherProperty.name,
              IconShiftStatus.requiresNewBuild,
              name,
              applied: shown,
              message:
                  'iOS has no public API to change an installed app\'s Home '
                  'Screen name: it is CFBundleDisplayName in the signed '
                  'bundle, and setAlternateIconName changes only the icon. '
                  'Only a new build changes it.',
            );
    }
    return _launcherResult(
      LauncherProperty.name,
      IconShiftStatus.unsupported,
      name,
      message:
          '${_platformName()} has no launcher name an app can change at '
          'runtime. setDisplayName() changes the window / tab title instead.',
    );
  }

  /// Changes the installed app's own launcher **icon** to [iconKey] — a
  /// variant id from the configuration whose icon is compiled into the app:
  ///
  /// * **Android** — enables the activity-alias of [iconKey]. Each alias
  ///   carries one icon and one label, so when that variant has a different
  ///   name the launcher name changes too (the result says so). Deferred
  ///   like [changeLauncherName] unless [immediate].
  /// * **iOS** — `setAlternateIconName` with the alternate icon set of
  ///   [iconKey] (iOS shows its own confirmation alert). The Home Screen
  ///   name does not change.
  /// * **macOS, Windows, Linux, web** — [IconShiftStatus.unsupported]: their
  ///   launcher icon is part of the build. [setIcon] changes the running
  ///   app's Dock/taskbar icon or favicon instead.
  ///
  /// `default` restores the icon the app shipped with.
  Future<LauncherResult> changeLauncherIcon(
    String iconKey, {
    bool immediate = false,
  }) async {
    _requireInitialized();
    if (iconKey.trim().isEmpty) {
      throw const InvalidArgumentException(
        'changeLauncherIcon needs an icon key.',
      );
    }
    final known = config.hasVariant(iconKey);

    if (_capabilities.iconAndNameLinked) {
      return _switchLauncherEntry(
        LauncherProperty.icon,
        iconKey,
        immediate: immediate,
        pick: (identities, current) {
          if (!known) return null;
          // Prefer an alias with this icon and the current name.
          final wanted = _resolve(iconKey).icon;
          final currentName = _resolve(current).name;
          final sameIcon = identities.where(
            (i) => config.hasVariant(i.id) && _resolve(i.id).icon == wanted,
          );
          return sameIcon
                  .where((i) => _resolve(i.id).name == currentName)
                  .firstOrNull ??
              identities.where((i) => i.id == iconKey).firstOrNull;
        },
        missing: (_) =>
            'No launcher entry with the icon of "$iconKey" is compiled into '
            'this app, so nothing was changed.',
      );
    }

    if (targetPlatform == IconShiftPlatform.ios) {
      if (!_capabilities.icon.isSupported) {
        return _launcherResult(
          LauncherProperty.icon,
          IconShiftStatus.unsupported,
          iconKey,
          message: _capabilities.icon.limitation,
        );
      }
      if (!known) {
        return _launcherResult(
          LauncherProperty.icon,
          IconShiftStatus.requiresPreconfiguredLauncher,
          iconKey,
          message: '"$iconKey" is not a variant in the configuration.',
        );
      }
      final key = _nativeIconKey(iconKey);
      final before = await _nativeIconKeyNow();
      final result = await _serialize(
        () => _setIdentity(iconKey, IconShiftOperation.setIcon),
      );
      final after = await _nativeIconKeyNow();
      final outcome = result.icon;
      if (!outcome.isSuccessful) {
        return _launcherResult(
          LauncherProperty.icon,
          outcome.errorCode == IconShiftErrorCode.missingNativeResource
              ? IconShiftStatus.requiresPreconfiguredLauncher
              : IconShiftStatus.platformError,
          iconKey,
          applied: after,
          details: result,
          message: outcome.message,
        );
      }
      return _launcherResult(
        LauncherProperty.icon,
        after == key ? IconShiftStatus.success : IconShiftStatus.failed,
        iconKey,
        applied: after,
        changed: after != before,
        details: result,
        message: after == key
            ? 'The Home Screen name is unchanged: alternate icons carry no name.'
            : 'iOS reports the icon "$after" after switching to "$key".',
      );
    }

    return _launcherResult(
      LauncherProperty.icon,
      IconShiftStatus.unsupported,
      iconKey,
      message:
          '${_platformName()} has no launcher icon an app can change at '
          'runtime. setIcon() changes the running app\'s icon instead.',
    );
  }

  /// Android: switches the enabled activity-alias to the identity [pick]
  /// chooses, then reads PackageManager back.
  Future<LauncherResult> _switchLauncherEntry(
    LauncherProperty property,
    String requested, {
    required bool immediate,
    required NativeLauncherIdentity? Function(
      List<NativeLauncherIdentity> identities,
      String currentVariant,
    )
    pick,
    required String Function(List<String> available) missing,
  }) async {
    String? appliedOf(NativeLauncherIdentity i) =>
        property == LauncherProperty.name ? i.label : i.id;

    final List<NativeLauncherIdentity> identities;
    try {
      identities = await platform.getLauncherIdentities();
    } on Object catch (e) {
      return _launcherResult(
        property,
        IconShiftStatus.platformError,
        requested,
        message: 'Could not read the launcher identities: $e',
      );
    }
    final available = [
      for (final v in {for (final i in identities) ?appliedOf(i)}) v,
    ];
    final before = identities.where((i) => i.enabled).toList();
    final current = before.length == 1 ? before.single : null;
    final target = pick(identities, current?.id ?? await _activeVariant());
    if (target == null) {
      return _launcherResult(
        property,
        IconShiftStatus.requiresPreconfiguredLauncher,
        requested,
        applied: current == null ? null : appliedOf(current),
        enabled: before.length,
        available: available,
        message: missing(available),
      );
    }
    if (current?.id == target.id) {
      return _launcherResult(
        property,
        IconShiftStatus.success,
        requested,
        applied: appliedOf(target),
        enabled: 1,
        available: available,
      );
    }

    final result = await _serialize(
      () => _setIdentity(
        target.id,
        IconShiftOperation.setIdentity,
        immediate: immediate,
      ),
    );
    final outcome = result.icon;
    if (outcome.status == OperationStatus.pending) {
      return _launcherResult(
        property,
        IconShiftStatus.pending,
        requested,
        applied: current == null ? null : appliedOf(current),
        enabled: before.length,
        available: available,
        details: result,
        message:
            'Switches to "${target.label}" when the app leaves the foreground: '
            'this screen was opened through the launcher entry being '
            'replaced, and Android closes such a screen. Pass immediate: true '
            'to switch now and let it close.',
      );
    }
    if (!outcome.isSuccessful) {
      return _launcherResult(
        property,
        IconShiftStatus.platformError,
        requested,
        applied: current == null ? null : appliedOf(current),
        enabled: before.length,
        available: available,
        details: result,
        message: outcome.message,
      );
    }
    final after = (await platform.getLauncherIdentities())
        .where((i) => i.enabled)
        .toList();
    final applied = after.length == 1 ? appliedOf(after.single) : null;
    final expected = appliedOf(target);
    if (after.length != 1 || applied != expected) {
      return _launcherResult(
        property,
        IconShiftStatus.failed,
        requested,
        applied: applied,
        changed: true,
        enabled: after.length,
        available: available,
        details: result,
        message:
            'PackageManager reports ${after.length} enabled launcher '
            'entr${after.length == 1 ? 'y' : 'ies'} '
            '(${after.map((i) => '"${i.label}"').join(', ')}) after '
            'switching to "${target.id}".',
      );
    }
    final nameChanged = current != null && current.label != target.label;
    final iconChanged =
        current != null &&
        config.hasVariant(current.id) &&
        _resolve(current.id).icon != _resolve(target.id).icon;
    return _launcherResult(
      property,
      IconShiftStatus.success,
      requested,
      applied: applied,
      changed: true,
      enabled: 1,
      available: available,
      details: result,
      refresh: LauncherRefresh.expected,
      message: switch (property) {
        LauncherProperty.name when iconChanged =>
          'Identity "${target.id}" carries this name with its own icon, so '
              'the icon changed too.',
        LauncherProperty.icon when nameChanged =>
          'Identity "${target.id}" carries this icon with the name '
              '"${target.label}", so the launcher name changed too.',
        _ => null,
      },
    );
  }

  LauncherResult _launcherResult(
    LauncherProperty property,
    IconShiftStatus status,
    String requested, {
    String? applied,
    bool changed = false,
    int? enabled,
    List<String> available = const [],
    LauncherRefresh refresh = LauncherRefresh.notApplicable,
    IconShiftResult? details,
    String? message,
  }) => LauncherResult(
    property: property,
    status: status,
    requestedValue: requested,
    appliedValue: applied,
    platform: targetPlatform,
    changed: changed,
    enabledEntries: enabled,
    availableValues: available,
    launcherRefresh: refresh,
    details: details,
    message: message,
  );

  /// The icon key the OS reports right now, without the dark suffix.
  Future<String?> _nativeIconKeyNow() async {
    try {
      return _logicalKey((await platform.getNativeState()).iconKey);
    } on Object {
      return null;
    }
  }

  /// The installed app's launcher identity, as far as the OS reports it.
  Future<LauncherIdentity> _launcherIdentity(NativeIdentityState native) async {
    switch (targetPlatform) {
      case IconShiftPlatform.android:
        final enabled = (await _launcherIdentitiesOrEmpty())
            .where((i) => i.enabled)
            .toList();
        final one = enabled.length == 1 ? enabled.single : null;
        return LauncherIdentity(
          platform: targetPlatform,
          name: one?.label,
          iconKey: one?.id,
          isNameVerified: one != null,
          isIconVerified: one != null,
          pendingIconKey: _logicalKey(native.pendingIconKey),
        );
      case IconShiftPlatform.ios:
        final name = await _appEntryName();
        final icon = _logicalKey(native.iconKey);
        return LauncherIdentity(
          platform: targetPlatform,
          name: name,
          iconKey: icon,
          isNameVerified: name != null,
          isIconVerified: icon != null,
        );
      default:
        // The launcher entry of a desktop app or PWA belongs to its
        // installer; IconShift cannot read it reliably.
        return LauncherIdentity(platform: targetPlatform);
    }
  }

  /// The launcher names of this install, read from the OS.
  Future<LauncherNameInfo> getLauncherName() async {
    _requireInitialized();
    final identities = await _launcherIdentitiesOrEmpty();
    return LauncherNameInfo(
      appEntryName:
          identities.where((i) => i.enabled).singleOrNull?.label ??
          (targetPlatform == IconShiftPlatform.ios
              ? await _appEntryName()
              : null),
      requestedName: _selection[_Keys.launcherName],
      availableNames: {for (final i in identities) i.label}.toList(),
      canSwitchAppEntry: _capabilities.canChangeLauncherName,
    );
  }

  /// Applies the last requested launcher name again. `null` when no name
  /// was requested.
  Future<LauncherResult?> refreshLauncherName() async {
    _requireInitialized();
    final name = _selection[_Keys.launcherName];
    if (name == null) return null;
    return changeLauncherName(name);
  }

  Future<List<NativeLauncherIdentity>> _launcherIdentitiesOrEmpty() async {
    if (!_capabilities.iconAndNameLinked) return const [];
    try {
      return await platform.getLauncherIdentities();
    } on Object {
      return const [];
    }
  }

  /// The app entry's name as the OS reports it.
  Future<String?> _appEntryName() async {
    try {
      return (await platform.getApplicationInfo()).displayName;
    } on Object {
      return null;
    }
  }

  /// Downloads and parses the [RemoteIcon] JSON at [url].
  Future<RemoteIcon> fetchRemoteIcon(Uri url) async {
    checkRemoteIconUrl(url);
    final Uint8List bytes;
    try {
      bytes = await _fetch(url, maxBytes: 256 * 1024);
    } on Object catch (e) {
      throw InvalidArgumentException('Could not download $url: $e');
    }
    return RemoteIcon.decode(utf8.decode(bytes), baseUri: url);
  }

  /// Re-applies the current icon for the system appearance, so that its
  /// dark artwork is shown in dark mode. Only platforms that apply images at
  /// runtime are affected; iOS switches icon appearances by itself.
  Future<IconShiftResult?> refreshAppearance() {
    _requireInitialized();
    if (!_capabilities.icon.isSupported ||
        !_capabilities.icon.acceptsArbitraryValues) {
      return Future.value();
    }
    return _serialize(() async {
      final OperationOutcome icon;
      if (_savedRemote() case final remote?) {
        icon = await _applyRemoteIcon(remote);
      } else {
        icon = (await _applyIcon(_selection[_Keys.icon] ?? _defaultId)).outcome;
      }
      if (icon.status == OperationStatus.unchanged) return null;
      return _result(
        IconShiftOperation.setIcon,
        icon,
        const OperationOutcome.notRequested(),
      );
    });
  }

  Future<IconShiftResult> restoreDefault() {
    _requireInitialized();
    return _serialize(() async {
      final result = await _setIdentity(
        _defaultId,
        IconShiftOperation.restoreDefault,
      );
      if (result.isComplete) await _saveSelection({});
      return result;
    });
  }

  // ---------------------------------------------------------------------------
  // Queries

  Future<IconShiftCapabilities> getCapabilities() async {
    _requireInitialized();
    return _capabilities;
  }

  Future<IconShiftState> getCurrentIdentity() async {
    _requireInitialized();
    NativeIdentityState native;
    try {
      native = await platform.getNativeState();
    } on Object catch (e) {
      debugPrint('IconShift: could not read native state: $e');
      native = const NativeIdentityState();
    }
    return IconShiftState(
      platform: targetPlatform,
      requestedIdentity: _selection[_Keys.identity],
      requestedIconVariant: _selection[_Keys.icon],
      requestedDisplayName: _selection[_Keys.name],
      nativeIconVariant: _logicalKey(native.iconKey),
      nativeDisplayName: native.displayName,
      pendingIconVariant: _logicalKey(native.pendingIconKey),
      launcher: await _launcherIdentity(native),
    );
  }

  Future<List<IdentityVariant>> getVariants() async {
    _requireInitialized();
    final inspection = await _inspect();
    final state = await getCurrentIdentity();
    final currentKey = state.pendingIconVariant ?? state.currentIconVariant;
    return [
      for (final id in config.variantIds)
        _variantInfo(id, inspection, currentKey),
    ];
  }

  Future<IconShiftValidationResult> validateConfiguration() async {
    _requireInitialized();
    final issues = <ValidationIssue>[
      ...validateConfig(config).issues,
      ...await _checkAssets(),
      ...(await _inspect()).issues,
    ];
    return IconShiftValidationResult(List.unmodifiable(issues));
  }

  Future<IconShiftDiagnostics> getDiagnostics() async {
    _requireInitialized();
    final inspection = await _inspect();
    return IconShiftDiagnostics(
      platform: targetPlatform,
      capabilities: _capabilities,
      state: await getCurrentIdentity(),
      validation: await validateConfiguration(),
      nativeInfo: inspection.info,
      restoreResult: _restoreResult,
    );
  }

  Future<PlatformCapabilities> getPlatformCapabilities() async {
    _requireInitialized();
    return PlatformCapabilities(
      platform: targetPlatform,
      runtime: _capabilities,
      properties: targetPlatform == null
          ? const {}
          : identityPropertiesFor(targetPlatform!),
    );
  }

  Future<ApplicationInfo> getApplicationInfo() async {
    _requireInitialized();
    ApplicationInfo info;
    try {
      info = await platform.getApplicationInfo();
    } on Object catch (e) {
      debugPrint('IconShift: could not read application info: $e');
      info = ApplicationInfo(platform: targetPlatform);
    }
    final state = await getCurrentIdentity();
    return info.copyWith(currentIconVariant: state.nativeIconVariant);
  }

  /// What applying [variantId] would do here and on every platform.
  Future<IdentityPreview> previewIdentity(String variantId) async {
    _requireVariant(variantId);
    final platforms = <IconShiftPlatform, PlatformIdentityPreview>{};
    for (final p in IconShiftPlatform.values) {
      final r = config.resolve(variantId, p, locale: locale);
      final table = identityPropertiesFor(p);
      platforms[p] = PlatformIdentityPreview(
        displayName: r.name,
        icon: r.icon,
        usesDefaultName: r.usesDefaultName,
        usesDefaultIcon: r.usesDefaultIcon,
        nameAppliesAtRuntime:
            table[IdentityProperty.displayName]!.isRuntimeChangeable ||
            table[IdentityProperty.windowTitle]!.isRuntimeChangeable,
        iconAppliesAtRuntime:
            table[IdentityProperty.launcherIcon]!.isRuntimeChangeable ||
            table[IdentityProperty.runningAppIcon]!.isRuntimeChangeable,
      );
    }

    final warnings = <ValidationIssue>[
      ...(await validateConfiguration()).issuesFor(variantId),
    ];
    void warn(String code, String message) => warnings.add(
      ValidationIssue(
        severity: ValidationSeverity.warning,
        code: code,
        message: message,
        variantId: variantId,
        platform: targetPlatform,
      ),
    );
    if (targetPlatform != null) {
      final r = _resolve(variantId);
      if (!r.usesDefaultIcon && !_capabilities.icon.isSupported) {
        warn(
          'icon_not_applied',
          'The icon will not change here: ${_capabilities.icon.limitation ?? 'unsupported'}',
        );
      }
      if (!r.usesDefaultName && !_capabilities.displayName.isSupported) {
        warn(
          'name_not_applied',
          'The name "${r.name}" will not be shown here: '
              '${_capabilities.displayName.limitation ?? 'unsupported'}',
        );
      }
    }
    return IdentityPreview(
      variantId: variantId,
      platforms: platforms,
      currentPlatform: targetPlatform,
      warnings: List.unmodifiable(warnings),
    );
  }

  /// Forgets the saved selection without changing what the OS shows.
  Future<void> clearSavedSelection() async {
    _requireInitialized();
    await _serialize(() => _saveSelection({}));
  }

  // ---------------------------------------------------------------------------
  // Internals

  Future<IconShiftResult> _setIdentity(
    String variantId,
    IconShiftOperation operation, {
    bool immediate = false,
  }) async {
    final resolved = _resolve(variantId);
    final icon = await _applyIcon(variantId, immediate: immediate);

    final OperationOutcome name;
    if (_capabilities.iconAndNameLinked) {
      name = _linkedNameOutcome(icon.outcome, variantId, icon.linkedName);
    } else if (icon.outcome.status == OperationStatus.failed) {
      name = _skippedAfterIconFailure;
    } else if (resolved.usesDefaultName &&
        !_capabilities.displayName.isSupported) {
      // Nothing differs from the shipped name, so nothing is lost.
      name = const OperationOutcome.notRequested();
    } else {
      name = await _applyName(resolved.usesDefaultName ? null : resolved.name);
    }

    await _commit(icon.outcome, {
      _Keys.icon: _storedIconKey(variantId),
      _Keys.remote: null,
      // The alias label replaces any custom name (Android task label).
      if (_capabilities.iconAndNameLinked) _Keys.name: null,
    });
    if (!_capabilities.iconAndNameLinked) {
      await _commit(name, {
        _Keys.name: resolved.usesDefaultName ? null : resolved.name,
      });
    }
    if (icon.outcome.isSuccessful || name.isSuccessful) {
      await _commit(const OperationOutcome.applied(), {
        _Keys.identity: variantId == _defaultId ? null : variantId,
      });
      await _applyThemeColor(variantId);
    }
    return _result(operation, icon.outcome, name);
  }

  Future<({OperationOutcome outcome, String? linkedName})> _applyIcon(
    String variantId, {
    bool immediate = false,
  }) async {
    if (!_capabilities.icon.isSupported) {
      return (
        outcome: OperationOutcome.unsupported(
          _capabilities.icon.limitation ??
              'Changing the icon is not supported on ${_platformName()}.',
        ),
        linkedName: null,
      );
    }
    final resolved = _resolve(variantId);
    final dark = _showsDarkArtwork(resolved.appearances.dark);
    final key = dark
        ? '${_nativeIconKey(variantId)}$_darkSuffix'
        : _nativeIconKey(variantId);

    Uint8List? bytes;
    final icon = dark ? resolved.appearances.dark : resolved.icon;
    final needsBytes =
        key != defaultIconKey &&
        _capabilities.icon.acceptsArbitraryValues &&
        targetPlatform != IconShiftPlatform.web;
    if (needsBytes) {
      if (icon == null) {
        return (
          outcome: OperationOutcome.failed(
            IconShiftErrorCode.missingNativeResource,
            'Variant "$variantId" has no icon for ${_platformName()}.',
          ),
          linkedName: null,
        );
      }
      try {
        bytes = (await _assets.load(icon.assetKey)).buffer.asUint8List();
      } on Object {
        return (
          outcome: OperationOutcome.failed(
            IconShiftErrorCode.missingAsset,
            'Could not load icon asset "${icon.assetKey}".',
          ),
          linkedName: null,
        );
      }
    }

    try {
      final native = await platform.setIcon(
        NativeIconRequest(
          key: key,
          assetKey: key == defaultIconKey ? null : icon?.assetKey,
          bytes: bytes,
          immediate: immediate,
        ),
      );
      return (
        outcome: _outcomeFromNative(native),
        linkedName: native.displayName,
      );
    } on Object catch (e) {
      return (outcome: _outcomeFromError(e), linkedName: null);
    }
  }

  Future<OperationOutcome> _applyName(String? name) async {
    final capability = _capabilities.displayName;
    if (!capability.isSupported) {
      final buildTime = _property(IdentityProperty.displayName)?.buildTime;
      return OperationOutcome.unsupported(
        capability.limitation ??
            'Changing the display name is not supported on '
                '${_platformName()}.',
        code: buildTime == true
            ? IconShiftErrorCode.buildRequired
            : IconShiftErrorCode.unsupportedOperation,
      );
    }
    if (!capability.acceptsArbitraryValues) {
      return OperationOutcome.unsupported(
        capability.limitation ??
            'On ${_platformName()} the display name can only change together '
                'with the icon. Use setIdentity() with a preconfigured '
                'variant.',
      );
    }
    try {
      return _outcomeFromNative(await platform.setDisplayName(name));
    } on Object catch (e) {
      return _outcomeFromError(e);
    }
  }

  /// Downloads (except on web) and applies [remote], in its dark artwork
  /// when the system is in dark mode.
  Future<OperationOutcome> _applyRemoteIcon(RemoteIcon remote) async {
    if (!_capabilities.icon.isSupported) {
      return OperationOutcome.unsupported(
        _capabilities.icon.limitation ??
            'Changing the icon is not supported on ${_platformName()}.',
      );
    }
    final dark = _showsDarkArtwork(remote.dark);
    final url = dark ? remote.dark! : remote.url;
    final key = '$_remotePrefix${remote.key}${dark ? _darkSuffix : ''}';
    Uint8List? bytes;
    if (targetPlatform != IconShiftPlatform.web) {
      try {
        bytes = await _fetch(url, maxBytes: maxRemoteIconBytes);
      } on Object catch (e) {
        return OperationOutcome.failed(
          IconShiftErrorCode.downloadFailed,
          'Could not download $url: $e',
        );
      }
      if (!looksLikeImage(bytes)) {
        return OperationOutcome.failed(
          IconShiftErrorCode.downloadFailed,
          '$url did not return a PNG, JPEG, GIF, BMP, WebP or ICO image.',
        );
      }
    }
    try {
      return _outcomeFromNative(
        await platform.setIcon(
          NativeIconRequest(key: key, bytes: bytes, url: url),
        ),
      );
    } on Object catch (e) {
      return _outcomeFromError(e);
    }
  }

  /// Whether to show [darkArtwork] instead of the regular icon: only where
  /// IconShift applies images itself (iOS picks appearances on its own).
  bool _showsDarkArtwork(Object? darkArtwork) =>
      darkArtwork != null &&
      _capabilities.icon.acceptsArbitraryValues &&
      _systemAppearance?.call() == IconAppearanceMode.dark;

  RemoteIcon? _savedRemote() {
    final json = _selection[_Keys.remote];
    if (json == null) return null;
    try {
      return RemoteIcon.decode(json);
    } on Object {
      return null;
    }
  }

  /// [key] as the variant it shows: without the dark suffix.
  static String? _logicalKey(String? key) =>
      key != null && key.endsWith(_darkSuffix)
      ? key.substring(0, key.length - _darkSuffix.length)
      : key;

  OperationOutcome _linkedNameOutcome(
    OperationOutcome icon,
    String variantId,
    String? label,
  ) {
    final platformName = _platformName();
    return switch (icon.status) {
      OperationStatus.applied || OperationStatus.pending => OperationOutcome(
        icon.status,
        message:
            'On $platformName icon and label are linked; the label of '
            'variant "$variantId"${label == null ? '' : ' ("$label")'} is '
            'now active.',
      ),
      OperationStatus.unchanged => const OperationOutcome(
        OperationStatus.unchanged,
      ),
      OperationStatus.failed ||
      OperationStatus.skipped => _skippedAfterIconFailure,
      OperationStatus.unsupported || OperationStatus.notRequested => icon,
    };
  }

  /// The variant the OS shows now (Android: the enabled alias).
  Future<String> _activeVariant() async {
    try {
      final key = _logicalKey((await platform.getNativeState()).iconKey);
      final id = key == null ? null : config.migrateVariantId(key);
      if (id != null) return id;
    } on Object catch (e) {
      debugPrint('IconShift: could not read native state: $e');
    }
    return _selection[_Keys.identity] ?? _selection[_Keys.icon] ?? _defaultId;
  }

  /// Linked platforms: the variant that shows [name] with the icon of
  /// [iconVariant], so the launcher label can change without changing the
  /// picture. `null` when no variant has that combination.
  String? _linkedVariantFor(String iconVariant, String name) {
    if (!config.hasVariant(iconVariant)) return null;
    final icon = _resolve(iconVariant).icon;
    final matches = [
      for (final id in config.variantIds)
        if (_resolve(id) case final r when r.name == name && r.icon == icon) id,
    ];
    if (matches.contains(iconVariant)) return iconVariant;
    return matches.isEmpty ? null : matches.first;
  }

  /// Linked platforms: a custom name only reaches the recent-apps label;
  /// says so, and which launcher names exist, instead of a bare "applied".
  OperationOutcome _explainLinked(OperationOutcome outcome, String name) {
    if (!_capabilities.iconAndNameLinked || !outcome.isSuccessful) {
      return outcome;
    }
    final names = {
      for (final id in config.variantIds) ?_resolve(id).name,
    }.map((n) => '"$n"').join(', ');
    return OperationOutcome(
      outcome.status,
      message:
          '"$name" is shown in the recent-apps screen only. The launcher can '
          'only show names compiled into the app ($names); add a variant '
          'named "$name" to icon_shift.yaml and run icon_shift_cli generate '
          'to make it a launcher name.',
    );
  }

  static const _skippedAfterIconFailure = OperationOutcome.skipped(
    'Not applied because the icon change failed, to keep icon and name '
    'consistent.',
  );

  /// Native key for the icon of [variantId].
  String _nativeIconKey(String variantId) {
    if (variantId == _defaultId) return defaultIconKey;
    // Android: every variant is its own activity-alias (icon + label).
    if (_capabilities.iconAndNameLinked) return variantId;
    return _resolve(variantId).usesDefaultIcon ? defaultIconKey : variantId;
  }

  /// Value persisted as the requested icon: `null` for the shipped icon.
  String? _storedIconKey(String variantId) {
    final key = _nativeIconKey(variantId);
    return key == defaultIconKey ? null : key;
  }

  IdentityVariant _variantInfo(
    String id,
    NativeInspection inspection,
    String currentKey,
  ) {
    final resolved = _resolve(id);
    final errors = inspection.issues.where(
      (i) => i.variantId == id && i.severity == ValidationSeverity.error,
    );
    final String? reason;
    if (!_capabilities.supportsVariants) {
      reason =
          _capabilities.icon.limitation ??
          'IconShift cannot change the identity on ${_platformName()}.';
    } else {
      reason = errors.isEmpty ? null : errors.first.message;
    }
    return IdentityVariant(
      id: id,
      isDefault: id == _defaultId,
      displayName: resolved.name,
      previewIcon: resolved.icon,
      isAvailable: reason == null,
      unavailableReason: reason,
      isCurrentIcon: _nativeIconKey(id) == currentKey,
    );
  }

  Future<IconShiftResult?> _restore() async {
    var icon = const OperationOutcome.notRequested();
    var name = const OperationOutcome.notRequested();

    final iconKey = _selection[_Keys.icon];
    final remote = _savedRemote();
    final reapplies =
        _capabilities.icon.isSupported && !_capabilities.icon.persistsNatively;
    if (remote != null && reapplies) {
      icon = await _applyRemoteIcon(remote);
    } else if (reapplies &&
        (iconKey != null ||
            _showsDarkArtwork(_resolve(_defaultId).appearances.dark))) {
      // The default icon only needs applying for its dark artwork.
      icon = (await _applyIcon(iconKey ?? _defaultId)).outcome;
    }
    final savedName = _selection[_Keys.name];
    if (savedName != null &&
        _capabilities.displayName.isSupported &&
        _capabilities.displayName.acceptsArbitraryValues &&
        !_capabilities.displayName.persistsNatively) {
      name = await _applyName(savedName);
    }

    if (_selection[_Keys.identity] case final identity?) {
      await _applyThemeColor(identity);
    }
    if (icon.status == OperationStatus.notRequested &&
        name.status == OperationStatus.notRequested) {
      return null;
    }
    final result = _result(IconShiftOperation.initialize, icon, name);
    if (!result.isComplete) {
      debugPrint('IconShift: re-applying the saved selection: $result');
    }
    return result;
  }

  /// Repairs the saved selection after an app update or corruption: unknown
  /// keys are dropped, renamed variants are migrated via
  /// [IconShiftConfig.renamedVariants], removed ones are forgotten, invalid
  /// names are discarded.
  Future<void> _recoverSelection() async {
    final recovered = <String, String>{};
    final notes = <String>[];
    _selection.forEach((key, value) {
      switch (key) {
        case _Keys.identity || _Keys.icon:
          final migrated = config.migrateVariantId(value);
          if (migrated == null) {
            notes.add('$key "$value" no longer exists');
          } else if (migrated == _defaultId) {
            if (migrated != value) notes.add('$key "$value" → default');
          } else {
            if (migrated != value) notes.add('$key "$value" → "$migrated"');
            recovered[key] = key == _Keys.icon
                ? (_storedIconKey(migrated) ?? '')
                : migrated;
          }
        case _Keys.branding:
          try {
            jsonDecode(value);
            recovered[key] = value;
          } on Object {
            notes.add('invalid cached branding dropped');
          }
        case _Keys.brandingTenant:
          recovered[key] = value;
        case _Keys.launcherName:
          if (displayNameProblem(value) == null) recovered[key] = value;
        case _Keys.remote:
          try {
            RemoteIcon.decode(value);
            recovered[key] = value;
          } on Object {
            notes.add('invalid saved remote icon dropped');
          }
        case _Keys.name:
          if (displayNameProblem(value) == null) {
            recovered[key] = value;
          } else {
            notes.add('invalid saved name dropped');
          }
        default:
          notes.add('unknown key "$key" dropped');
      }
    });
    recovered.removeWhere((_, v) => v.isEmpty);
    if (mapEquals(recovered, _selection)) return;
    debugPrint(
      'IconShift: recovered the saved selection (${notes.join('; ')}).',
    );
    await _saveSelection(recovered);
  }

  IconShiftResult _result(
    IconShiftOperation operation,
    OperationOutcome icon,
    OperationOutcome name,
  ) => IconShiftResult(
    icon: icon.withSuggestion(_suggestion(icon, IdentityProperty.launcherIcon)),
    displayName: name.withSuggestion(
      _suggestion(name, IdentityProperty.displayName),
    ),
    operation: operation,
    platform: targetPlatform,
  );

  PropertySupport? _property(IdentityProperty property) =>
      targetPlatform == null
      ? null
      : identityPropertiesFor(targetPlatform!)[property];

  /// A fix for [outcome], if IconShift knows one.
  String? _suggestion(OperationOutcome outcome, IdentityProperty property) {
    return switch (outcome.errorCode) {
      IconShiftErrorCode.missingAsset =>
        'List the image under flutter > assets in pubspec.yaml and rebuild.',
      IconShiftErrorCode.missingNativeResource => switch (targetPlatform) {
        IconShiftPlatform.android =>
          'Run `dart run icon_shift_cli generate`, rebuild, and check '
              'IconShift.validateConfiguration() for alias problems.',
        IconShiftPlatform.ios =>
          'Add an app icon set named like the variant (`icon_shift_cli '
              'generate`) and set ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS '
              '= YES, then rebuild.',
        _ => 'Check IconShift.validateConfiguration().',
      },
      IconShiftErrorCode.buildRequired =>
        property != IdentityProperty.displayName
            ? 'Change it at build time and rebuild.'
            : targetPlatform == IconShiftPlatform.ios
            ? 'iOS reads the home-screen name from the signed app. Set '
                  'default.name (and names: for translations) in '
                  'icon_shift.yaml, run `icon_shift_cli generate`, then '
                  'rebuild and reinstall.'
            : 'Set it at build time (application.display_name in '
                  'icon_shift.yaml, then `icon_shift_cli identity --apply`) '
                  'and rebuild.',
      IconShiftErrorCode.appNotActive =>
        'Call it while the app is in the foreground, e.g. from a button '
            'handler.',
      IconShiftErrorCode.downloadFailed =>
        'Check the URL, the network connection and (web) the server\'s CORS '
            'headers.',
      IconShiftErrorCode.nativeOperationFailed =>
        'See IconShift.getDiagnostics() for platform details.',
      _ => null,
    };
  }

  /// Web: applies the variant's theme color, or restores the page's own.
  Future<void> _applyThemeColor(String variantId) async {
    if (targetPlatform != IconShiftPlatform.web) return;
    final color = variantId == _defaultId || !config.hasVariant(variantId)
        ? null
        : _resolve(variantId).themeColor;
    try {
      await platform.setThemeColor(color);
    } on Object catch (e) {
      debugPrint('IconShift: could not set the theme color: $e');
    }
  }

  Future<List<ValidationIssue>> _checkAssets() async {
    final Set<String> available;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(_assets);
      available = manifest.listAssets().toSet();
    } on Object catch (e) {
      return [
        ValidationIssue(
          severity: ValidationSeverity.warning,
          code: 'asset_manifest_unavailable',
          message: 'Could not read the asset manifest to check icon assets: $e',
        ),
      ];
    }

    final issues = <ValidationIssue>[];
    final seen = <String>{};
    void check(AppIcon? icon, String variantId, IconShiftPlatform? platform) {
      if (icon == null || !seen.add(icon.assetKey)) return;
      if (!available.contains(icon.assetKey)) {
        issues.add(
          ValidationIssue(
            severity: ValidationSeverity.error,
            code: 'missing_asset',
            message:
                'Icon asset "${icon.assetKey}" is not bundled. Add it under '
                'flutter > assets in pubspec.yaml.',
            variantId: variantId,
            platform: platform,
          ),
        );
      }
    }

    void checkIdentity(String id, AppIdentity identity) {
      check(identity.icon, id, null);
      identity.platforms.forEach((p, o) => check(o.icon, id, p));
    }

    checkIdentity(_defaultId, config.defaultIdentity);
    config.variants.forEach(checkIdentity);
    return issues;
  }

  Future<NativeInspection> _inspect() async {
    if (!_capabilities.supportsVariants) return const NativeInspection();
    final specs = [
      for (final id in config.variantIds)
        () {
          final resolved = _resolve(id);
          return NativeVariantSpec(
            id: id,
            hasOwnIcon: id != _defaultId && !resolved.usesDefaultIcon,
            name: resolved.name,
          );
        }(),
    ];
    try {
      return await platform.inspect(specs);
    } on Object catch (e) {
      return NativeInspection(
        issues: [
          ValidationIssue(
            severity: ValidationSeverity.warning,
            code: 'native_inspection_failed',
            message: 'Native resource check failed: $e',
            platform: targetPlatform,
          ),
        ],
      );
    }
  }

  Future<IconShiftCapabilities> _loadCapabilities() async {
    if (targetPlatform == null) {
      return IconShiftCapabilities.none(
        null,
        'IconShift does not support this platform.',
      );
    }
    try {
      return await platform.getCapabilities();
    } on MissingPluginException {
      return IconShiftCapabilities.none(
        targetPlatform,
        'The IconShift native plugin is not registered. Rebuild the app '
        '(hot restart is not enough after adding a plugin).',
      );
    } on PlatformException catch (e) {
      return IconShiftCapabilities.none(
        targetPlatform,
        'Reading capabilities failed: ${e.message ?? e.code}',
      );
    }
  }

  Future<Map<String, String>> _loadSelection() async {
    try {
      return {...await platform.loadSelection()};
    } on Object catch (e) {
      debugPrint('IconShift: could not load the saved selection: $e');
      return {};
    }
  }

  /// Applies [changes] to the saved selection if [outcome] succeeded.
  /// A `null` value removes the key.
  Future<void> _commit(
    OperationOutcome outcome,
    Map<String, String?> changes,
  ) async {
    if (outcome.status == OperationStatus.notRequested ||
        !outcome.isSuccessful) {
      return;
    }
    final next = {..._selection};
    changes.forEach((key, value) {
      if (value == null) {
        next.remove(key);
      } else {
        next[key] = value;
      }
    });
    if (!mapEquals(next, _selection)) await _saveSelection(next);
  }

  void _publishDisplayName() {
    if (_config == null) return;
    final custom = _selection[_Keys.name];
    if (custom != null) {
      displayName.value = custom;
      return;
    }
    final id =
        _selection[_Keys.identity] ??
        (_capabilities.iconAndNameLinked ? _selection[_Keys.icon] : null);
    displayName.value = _resolve(
      id != null && config.hasVariant(id) ? id : _defaultId,
    ).name;
  }

  Future<void> _saveSelection(Map<String, String> selection) async {
    _selection = selection;
    _publishDisplayName();
    try {
      await platform.saveSelection(selection);
    } on Object catch (e) {
      debugPrint('IconShift: could not save the selection: $e');
    }
  }

  /// The cached branding JSON for [tenantId], or `null` when the cache
  /// belongs to another institution or is empty.
  String? readBranding(String tenantId) {
    _requireInitialized();
    if (_selection[_Keys.brandingTenant] != tenantId) return null;
    return _selection[_Keys.branding];
  }

  /// Replaces the cache with [json] for [tenantId], dropping whatever another
  /// institution had cached.
  Future<void> writeBranding(String tenantId, String json) {
    _requireInitialized();
    return _serialize(
      () => _saveSelection({
        ..._selection,
        _Keys.brandingTenant: tenantId,
        _Keys.branding: json,
      }),
    );
  }

  /// Forgets the cached branding (logout, or switching institution).
  Future<void> clearBranding() {
    _requireInitialized();
    if (!_selection.containsKey(_Keys.branding) &&
        !_selection.containsKey(_Keys.brandingTenant)) {
      return Future.value();
    }
    return _serialize(() {
      final next = {..._selection}
        ..remove(_Keys.branding)
        ..remove(_Keys.brandingTenant);
      return _saveSelection(next);
    });
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  void _requireInitialized() {
    if (_config == null) throw const NotInitializedException();
  }

  void _requireVariant(String variantId) {
    _requireInitialized();
    if (!config.hasVariant(variantId)) {
      throw VariantNotFoundException(variantId, config.variantIds);
    }
  }

  static void _requireValidName(String name) {
    final problem = displayNameProblem(name);
    if (problem != null) throw InvalidArgumentException(problem);
  }

  String _platformName() => targetPlatform?.name ?? 'this platform';

  static OperationOutcome _outcomeFromNative(NativeOperationResult native) {
    final status = switch (native.status) {
      'unchanged' => OperationStatus.unchanged,
      'pending' => OperationStatus.pending,
      _ => OperationStatus.applied,
    };
    return OperationOutcome(status, message: native.message);
  }

  static OperationOutcome _outcomeFromError(Object error) {
    if (error is MissingPluginException) {
      return const OperationOutcome.failed(
        IconShiftErrorCode.nativeOperationFailed,
        'The IconShift native plugin is not registered.',
      );
    }
    if (error is! PlatformException) {
      return OperationOutcome.failed(
        IconShiftErrorCode.nativeOperationFailed,
        error.toString(),
      );
    }
    final message = error.message ?? error.code;
    return switch (error.code) {
      NativeErrorCodes.unsupported => OperationOutcome.unsupported(message),
      NativeErrorCodes.missingResource => OperationOutcome.failed(
        IconShiftErrorCode.missingNativeResource,
        message,
      ),
      NativeErrorCodes.permissionDenied => OperationOutcome.failed(
        IconShiftErrorCode.permissionDenied,
        message,
      ),
      NativeErrorCodes.invalidArgument => OperationOutcome.failed(
        IconShiftErrorCode.invalidArgument,
        message,
      ),
      NativeErrorCodes.notActive => OperationOutcome.failed(
        IconShiftErrorCode.appNotActive,
        message,
      ),
      _ => OperationOutcome.failed(
        IconShiftErrorCode.nativeOperationFailed,
        message,
      ),
    };
  }
}
