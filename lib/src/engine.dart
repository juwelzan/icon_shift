import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'config/app_identity.dart';
import 'config/icon_shift_config.dart';
import 'config/platform.dart';
import 'exceptions.dart';
import 'models/capabilities.dart';
import 'models/diagnostics.dart';
import 'models/identity_variant.dart';
import 'models/result.dart';
import 'models/state.dart';
import 'models/validation.dart';
import 'platform/icon_shift_platform_interface.dart';
import 'validation/config_validator.dart';

/// Selection keys persisted through [IconShiftPlatformInterface.saveSelection].
abstract final class _Keys {
  static const identity = 'identity';
  static const icon = 'icon';
  static const name = 'name';
}

/// Implements IconShift on top of an [IconShiftPlatformInterface].
///
/// [IconShift] is a static facade over one instance of this class; tests can
/// construct it directly with a fake platform.
class IconShiftEngine {
  IconShiftEngine({
    required this.platform,
    required this.targetPlatform,
    AssetBundle? assetBundle,
  }) : _assets = assetBundle ?? rootBundle;

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
    await _dropStaleSelection();

    if (restoreSelection) _restoreResult = await _serialize(_restore);

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
    return _serialize(() => _setIdentity(variantId));
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
      });
      return IconShiftResult(
        icon: icon.outcome,
        displayName: const OperationOutcome.notRequested(),
      );
    });
  }

  Future<IconShiftResult> setDisplayName(String name) {
    _requireInitialized();
    _requireValidName(name);
    return _serialize(() async {
      final outcome = await _applyName(name);
      await _commit(outcome, {_Keys.identity: null, _Keys.name: name});
      return IconShiftResult(
        icon: const OperationOutcome.notRequested(),
        displayName: outcome,
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
      var icon = const OperationOutcome.notRequested();
      String? linkedName;
      if (iconVariant != null) {
        final applied = await _applyIcon(iconVariant);
        icon = applied.outcome;
        linkedName = applied.linkedName;
        await _commit(icon, {
          _Keys.identity: null,
          _Keys.icon: _storedIconKey(iconVariant),
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
        name = await _applyName(displayName);
        await _commit(name, {_Keys.identity: null, _Keys.name: displayName});
      }
      return IconShiftResult(icon: icon, displayName: name);
    });
  }

  Future<IconShiftResult> restoreDefault() {
    _requireInitialized();
    return _serialize(() async {
      final result = await _setIdentity(_defaultId);
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
      nativeIconVariant: native.iconKey,
      nativeDisplayName: native.displayName,
      pendingIconVariant: native.pendingIconKey,
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

  // ---------------------------------------------------------------------------
  // Internals

  Future<IconShiftResult> _setIdentity(String variantId) async {
    final resolved = config.resolve(variantId, targetPlatform);
    final icon = await _applyIcon(variantId);

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

    await _commit(icon.outcome, {_Keys.icon: _storedIconKey(variantId)});
    if (!_capabilities.iconAndNameLinked) {
      await _commit(name, {
        _Keys.name: resolved.usesDefaultName ? null : resolved.name,
      });
    }
    if (icon.outcome.isSuccessful || name.isSuccessful) {
      await _commit(const OperationOutcome.applied(), {
        _Keys.identity: variantId == _defaultId ? null : variantId,
      });
    }
    return IconShiftResult(icon: icon.outcome, displayName: name);
  }

  Future<({OperationOutcome outcome, String? linkedName})> _applyIcon(
    String variantId,
  ) async {
    if (!_capabilities.icon.isSupported) {
      return (
        outcome: OperationOutcome.unsupported(
          _capabilities.icon.limitation ??
              'Changing the icon is not supported on ${_platformName()}.',
        ),
        linkedName: null,
      );
    }
    final resolved = config.resolve(variantId, targetPlatform);
    final key = _nativeIconKey(variantId);

    Uint8List? bytes;
    final icon = resolved.icon;
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
            IconShiftErrorCode.missingNativeResource,
            'Could not load icon asset "${icon.assetKey}". Make sure it is '
            'listed under flutter > assets in pubspec.yaml.',
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
      return OperationOutcome.unsupported(
        capability.limitation ??
            'Changing the display name is not supported on '
                '${_platformName()}.',
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

  static const _skippedAfterIconFailure = OperationOutcome.skipped(
    'Not applied because the icon change failed, to keep icon and name '
    'consistent.',
  );

  /// Native key for the icon of [variantId].
  String _nativeIconKey(String variantId) {
    if (variantId == _defaultId) return defaultIconKey;
    // Android: every variant is its own activity-alias (icon + label).
    if (_capabilities.iconAndNameLinked) return variantId;
    return config.resolve(variantId, targetPlatform).usesDefaultIcon
        ? defaultIconKey
        : variantId;
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
    final resolved = config.resolve(id, targetPlatform);
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
    if (iconKey != null &&
        _capabilities.icon.isSupported &&
        !_capabilities.icon.persistsNatively) {
      icon = (await _applyIcon(iconKey)).outcome;
    }
    final savedName = _selection[_Keys.name];
    if (savedName != null &&
        _capabilities.displayName.isSupported &&
        _capabilities.displayName.acceptsArbitraryValues &&
        !_capabilities.displayName.persistsNatively) {
      name = await _applyName(savedName);
    }

    if (icon.status == OperationStatus.notRequested &&
        name.status == OperationStatus.notRequested) {
      return null;
    }
    final result = IconShiftResult(icon: icon, displayName: name);
    if (!result.isComplete) {
      debugPrint('IconShift: re-applying the saved selection: $result');
    }
    return result;
  }

  /// Forgets saved variants that are no longer configured.
  Future<void> _dropStaleSelection() async {
    final stale = [
      for (final key in [_Keys.identity, _Keys.icon])
        if (_selection[key] case final id? when !config.hasVariant(id)) key,
    ];
    if (stale.isEmpty) return;
    await _saveSelection(
      {..._selection}..removeWhere((k, _) => stale.contains(k)),
    );
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
          final resolved = config.resolve(id, targetPlatform);
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

  Future<void> _saveSelection(Map<String, String> selection) async {
    _selection = selection;
    try {
      await platform.saveSelection(selection);
    } on Object catch (e) {
      debugPrint('IconShift: could not save the selection: $e');
    }
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
