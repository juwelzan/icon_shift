import 'package:flutter_test/flutter_test.dart';
import 'package:icon_shift/icon_shift.dart';
import 'package:icon_shift/icon_shift_platform_interface.dart';
import 'package:icon_shift/icon_shift_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockIconShiftPlatform
    with MockPlatformInterfaceMixin
    implements IconShiftPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final IconShiftPlatform initialPlatform = IconShiftPlatform.instance;

  test('$MethodChannelIconShift is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelIconShift>());
  });

  test('getPlatformVersion', () async {
    IconShift iconShiftPlugin = IconShift();
    MockIconShiftPlatform fakePlatform = MockIconShiftPlatform();
    IconShiftPlatform.instance = fakePlatform;

    expect(await iconShiftPlugin.getPlatformVersion(), '42');
  });
}
