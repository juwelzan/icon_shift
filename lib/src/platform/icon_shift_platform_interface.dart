import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../models/application_info.dart';
import '../models/capabilities.dart';
import '../models/validation.dart';
import 'method_channel_icon_shift.dart';

/// Key for the shipped (default) icon in native requests and state.
const String defaultIconKey = 'default';

/// Request to change the icon.
@immutable
class NativeIconRequest {
  const NativeIconRequest({
    required this.key,
    this.assetKey,
    this.bytes,
    this.url,
    this.immediate = false,
  });

  /// Android: switch now even if it closes the visible screen. By default a
  /// switch that would disable the launcher entry the visible screen was
  /// opened through waits until the app leaves the foreground (`pending`).
  final bool immediate;

  /// Variant id of the icon, or [defaultIconKey] to restore the shipped icon.
  /// Dark artwork of a variant uses `<id>@dark`, remote icons
  /// `remote:<key>`.
  final String key;

  /// Remote image (web uses it directly as favicon URL).
  final Uri? url;

  /// Flutter asset key of the icon image (web uses it as favicon URL).
  final String? assetKey;

  /// Encoded image bytes for platforms that apply arbitrary images.
  final Uint8List? bytes;
}

/// Outcome of a successful native call. Failures are thrown as
/// `PlatformException` with one of the `NativeErrorCodes`.
@immutable
class NativeOperationResult {
  const NativeOperationResult(this.status, {this.message, this.displayName});

  factory NativeOperationResult.fromMap(Map<Object?, Object?>? map) =>
      NativeOperationResult(
        map?['status'] as String? ?? 'applied',
        message: map?['message'] as String?,
        displayName: map?['displayName'] as String?,
      );

  /// `applied`, `unchanged` or `pending`.
  final String status;
  final String? message;

  /// Display name that became active as a side effect (Android aliases).
  final String? displayName;
}

/// Error codes native implementations use in `PlatformException.code`.
abstract final class NativeErrorCodes {
  static const unsupported = 'unsupported';
  static const missingResource = 'missing_resource';
  static const permissionDenied = 'permission_denied';
  static const invalidArgument = 'invalid_argument';
  static const notActive = 'not_active';
  static const nativeFailure = 'native_failure';
}

/// Identity the OS reports right now.
@immutable
class NativeIdentityState {
  const NativeIdentityState({
    this.iconKey,
    this.displayName,
    this.pendingIconKey,
  });

  factory NativeIdentityState.fromMap(Map<Object?, Object?>? map) =>
      NativeIdentityState(
        iconKey: map?['iconKey'] as String?,
        displayName: map?['displayName'] as String?,
        pendingIconKey: map?['pendingIconKey'] as String?,
      );

  /// Active icon key, [defaultIconKey], or `null` if unknown.
  final String? iconKey;
  final String? displayName;
  final String? pendingIconKey;
}

/// What native code needs to know about a variant to check its resources.
@immutable
class NativeVariantSpec {
  const NativeVariantSpec({
    required this.id,
    required this.hasOwnIcon,
    this.name,
  });

  final String id;

  /// The variant defines its own icon for this platform (otherwise it uses
  /// the shipped icon and needs no alternate icon resource).
  final bool hasOwnIcon;

  /// Resolved display name for this platform.
  final String? name;

  Map<String, Object?> toMap() => {
    'id': id,
    'hasOwnIcon': hasOwnIcon,
    'name': name,
  };
}

/// Native resource check results.
@immutable
class NativeInspection {
  const NativeInspection({this.issues = const [], this.info = const {}});

  final List<ValidationIssue> issues;

  /// Platform facts for diagnostics. Must not contain user data.
  final Map<String, Object?> info;
}

/// One launcher identity compiled into the app (Android: an
/// activity-alias), as the OS reports it.
@immutable
class NativeLauncherIdentity {
  const NativeLauncherIdentity({
    required this.id,
    required this.label,
    required this.enabled,
    this.component,
  });

  factory NativeLauncherIdentity.fromMap(Map<Object?, Object?> map) =>
      NativeLauncherIdentity(
        id: map['id']! as String,
        label: map['label']! as String,
        enabled: map['enabled'] as bool? ?? false,
        component: map['component'] as String?,
      );

  /// Variant id the identity belongs to.
  final String id;

  /// The launcher label, as PackageManager resolves it for this device.
  final String label;

  /// This is the enabled launcher entry.
  final bool enabled;

  /// Component class name (Android).
  final String? component;

  @override
  String toString() =>
      'NativeLauncherIdentity($id: "$label"${enabled ? ', enabled' : ''})';
}

/// The interface each platform implementation of IconShift extends.
///
/// It works with native keys only; configuration logic lives in Dart
/// (`IconShiftEngine`). Implementations must extend this class (not
/// implement it) so new methods can be added without breaking them.
abstract class IconShiftPlatformInterface extends PlatformInterface {
  IconShiftPlatformInterface() : super(token: _token);

  static final Object _token = Object();

  static IconShiftPlatformInterface _instance = MethodChannelIconShift();

  /// The implementation in use. Defaults to [MethodChannelIconShift].
  static IconShiftPlatformInterface get instance => _instance;

  static set instance(IconShiftPlatformInterface instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<IconShiftCapabilities> getCapabilities();

  Future<NativeIdentityState> getNativeState();

  Future<NativeOperationResult> setIcon(NativeIconRequest request);

  /// Sets the display name, or restores the original one when [name] is
  /// `null`.
  Future<NativeOperationResult> setDisplayName(String? name);

  Future<NativeInspection> inspect(List<NativeVariantSpec> variants);

  Future<Map<String, String>> loadSelection();

  Future<void> saveSelection(Map<String, String> selection);

  /// Identity metadata the OS exposes about the running app.
  ///
  /// Implementations that predate this method report nothing rather than
  /// guessing.
  Future<ApplicationInfo> getApplicationInfo() async =>
      const ApplicationInfo(platform: null);

  /// The launcher identities compiled into the app. Empty where launcher
  /// identities do not exist (iOS, desktop, web).
  Future<List<NativeLauncherIdentity>> getLauncherIdentities() async =>
      const [];

  /// Sets the theme color (web: `<meta name="theme-color">`), or restores
  /// the original when [argb] is `null`. Unsupported by default.
  Future<NativeOperationResult> setThemeColor(int? argb) async =>
      throw PlatformException(
        code: NativeErrorCodes.unsupported,
        message: 'This platform has no runtime theme color.',
      );
}
