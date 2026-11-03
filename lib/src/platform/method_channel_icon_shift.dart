import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/platform.dart';
import '../models/application_info.dart';
import '../models/capabilities.dart';
import '../models/validation.dart';
import 'icon_shift_platform_interface.dart';
import 'version_json.dart';

/// [IconShiftPlatformInterface] backed by the `icon_shift` method channel,
/// used by the Android, iOS, macOS, Windows and Linux implementations.
class MethodChannelIconShift extends IconShiftPlatformInterface {
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel('icon_shift');

  @override
  Future<IconShiftCapabilities> getCapabilities() async {
    final map = await methodChannel.invokeMapMethod<Object?, Object?>(
      'getCapabilities',
    );
    return IconShiftCapabilities.fromMap(IconShiftPlatform.current, map ?? {});
  }

  @override
  Future<NativeIdentityState> getNativeState() async =>
      NativeIdentityState.fromMap(
        await methodChannel.invokeMapMethod<Object?, Object?>('getNativeState'),
      );

  @override
  Future<NativeOperationResult> setIcon(NativeIconRequest request) async =>
      NativeOperationResult.fromMap(
        await methodChannel.invokeMapMethod<Object?, Object?>('setIcon', {
          'key': request.key,
          'bytes': request.bytes,
        }),
      );

  @override
  Future<NativeOperationResult> setDisplayName(String? name) async =>
      NativeOperationResult.fromMap(
        await methodChannel.invokeMapMethod<Object?, Object?>(
          'setDisplayName',
          {'name': name},
        ),
      );

  @override
  Future<NativeInspection> inspect(List<NativeVariantSpec> variants) async {
    final map = await methodChannel.invokeMapMethod<Object?, Object?>(
      'inspect',
      {
        'variants': [for (final v in variants) v.toMap()],
      },
    );
    final platform = IconShiftPlatform.current;
    final issues = [
      for (final raw in (map?['issues'] as List<Object?>?) ?? const [])
        _issueFromMap(raw! as Map<Object?, Object?>, platform),
    ];
    final info = <String, Object?>{
      for (final MapEntry(:key, :value)
          in ((map?['info'] as Map<Object?, Object?>?) ?? const {}).entries)
        key.toString(): value,
    };
    return NativeInspection(issues: issues, info: info);
  }

  @override
  Future<Map<String, String>> loadSelection() async {
    final map = await methodChannel.invokeMapMethod<String, String>(
      'loadSelection',
    );
    return map ?? {};
  }

  @override
  Future<void> saveSelection(Map<String, String> selection) => methodChannel
      .invokeMethod<void>('saveSelection', {'selection': selection});

  @override
  Future<ApplicationInfo> getApplicationInfo() async {
    final map =
        await methodChannel.invokeMapMethod<Object?, Object?>(
          'getApplicationInfo',
        ) ??
        {};
    final platform = IconShiftPlatform.current;
    if (platform == IconShiftPlatform.linux && map['version'] == null) {
      map.addAll(readBundledVersionJson());
    }
    return ApplicationInfo.fromMap(platform, map);
  }

  static ValidationIssue _issueFromMap(
    Map<Object?, Object?> map,
    IconShiftPlatform? platform,
  ) {
    final severity = map['severity'] as String?;
    return ValidationIssue(
      severity: ValidationSeverity.values.firstWhere(
        (s) => s.name == severity,
        orElse: () => ValidationSeverity.warning,
      ),
      code: map['code'] as String? ?? 'native_issue',
      message: map['message'] as String? ?? '',
      variantId: map['variantId'] as String?,
      platform: platform,
    );
  }
}
