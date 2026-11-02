import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'icon_shift_platform_interface.dart';

/// An implementation of [IconShiftPlatform] that uses method channels.
class MethodChannelIconShift extends IconShiftPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('icon_shift');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
