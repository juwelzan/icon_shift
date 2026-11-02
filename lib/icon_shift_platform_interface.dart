import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'icon_shift_method_channel.dart';

abstract class IconShiftPlatform extends PlatformInterface {
  /// Constructs a IconShiftPlatform.
  IconShiftPlatform() : super(token: _token);

  static final Object _token = Object();

  static IconShiftPlatform _instance = MethodChannelIconShift();

  /// The default instance of [IconShiftPlatform] to use.
  ///
  /// Defaults to [MethodChannelIconShift].
  static IconShiftPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [IconShiftPlatform] when
  /// they register themselves.
  static set instance(IconShiftPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
