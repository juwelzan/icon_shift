
import 'icon_shift_platform_interface.dart';

class IconShift {
  Future<String?> getPlatformVersion() {
    return IconShiftPlatform.instance.getPlatformVersion();
  }
}
