import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:icon_shift/icon_shift.dart';
import 'package:icon_shift/icon_shift_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Capabilities resembling each real platform.
const androidLike = IconShiftCapabilities(
  platform: IconShiftPlatform.android,
  icon: OperationCapability(
    isSupported: true,
    scope: IdentityScope.launcher,
    persistsNatively: true,
    requiresPreconfiguredResources: true,
  ),
  displayName: OperationCapability(
    isSupported: true,
    scope: IdentityScope.launcher,
    persistsNatively: true,
    requiresPreconfiguredResources: true,
  ),
  iconAndNameLinked: true,
);

const iosLike = IconShiftCapabilities(
  platform: IconShiftPlatform.ios,
  icon: OperationCapability(
    isSupported: true,
    scope: IdentityScope.launcher,
    persistsNatively: true,
    requiresPreconfiguredResources: true,
  ),
  displayName: OperationCapability.unsupported('iOS cannot rename apps.'),
);

const desktopLike = IconShiftCapabilities(
  platform: IconShiftPlatform.macos,
  icon: OperationCapability(
    isSupported: true,
    scope: IdentityScope.runningApp,
    acceptsArbitraryValues: true,
  ),
  displayName: OperationCapability(
    isSupported: true,
    scope: IdentityScope.windowTitle,
    acceptsArbitraryValues: true,
  ),
);

/// Records calls and simulates a native side.
class FakePlatform extends IconShiftPlatformInterface
    with MockPlatformInterfaceMixin {
  FakePlatform(this.capabilities, {Map<String, String>? selection})
    : savedSelection = {...?selection};

  IconShiftCapabilities capabilities;
  Map<String, String> savedSelection;

  String iconKey = 'default';
  String? displayName = 'Shipped';
  String originalName = 'Shipped';

  /// Labels per alias, used when [IconShiftCapabilities.iconAndNameLinked].
  Map<String, String> aliasLabels = {};

  final calls = <String>[];
  final iconRequests = <NativeIconRequest>[];

  /// The shortcut as the launcher shows it.
  ShortcutIdentityState shortcut = const ShortcutIdentityState();
  final shortcutRequests = <NativeShortcutRequest>[];

  /// When set, setIcon throws this.
  PlatformException? iconError;
  PlatformException? nameError;
  PlatformException? shortcutError;
  List<ValidationIssue> inspectionIssues = [];

  @override
  Future<IconShiftCapabilities> getCapabilities() async => capabilities;

  @override
  Future<NativeIdentityState> getNativeState() async =>
      NativeIdentityState(iconKey: iconKey, displayName: displayName);

  @override
  Future<NativeOperationResult> setIcon(NativeIconRequest request) async {
    calls.add('setIcon:${request.key}');
    iconRequests.add(request);
    if (iconError != null) throw iconError!;
    if (request.key == iconKey) return const NativeOperationResult('unchanged');
    iconKey = request.key;
    final label = aliasLabels[request.key];
    if (label != null) displayName = label;
    return NativeOperationResult('applied', displayName: label);
  }

  @override
  Future<NativeOperationResult> setDisplayName(String? name) async {
    calls.add('setDisplayName:$name');
    if (nameError != null) throw nameError!;
    final target = name ?? originalName;
    if (target == displayName) return const NativeOperationResult('unchanged');
    displayName = target;
    return const NativeOperationResult('applied');
  }

  @override
  Future<ShortcutIdentityState> getShortcutState() async => shortcut;

  @override
  Future<NativeOperationResult> setShortcut(
    NativeShortcutRequest request,
  ) async {
    calls.add('setShortcut:${request.name}/${request.iconKey}');
    shortcutRequests.add(request);
    if (shortcutError != null) throw shortcutError!;
    final isFirst = !shortcut.isPinned;
    shortcut = ShortcutIdentityState(
      isSupported: true,
      isPinned: true,
      name: request.name ?? shortcut.name,
      iconKey: request.iconKey ?? shortcut.iconKey,
    );
    // The launcher asks the user the first time, then updates silently.
    return NativeOperationResult(isFirst ? 'pending' : 'applied');
  }

  @override
  Future<NativeOperationResult> disableShortcut(String message) async {
    calls.add('disableShortcut:$message');
    if (!shortcut.isPinned) return const NativeOperationResult('unchanged');
    shortcut = ShortcutIdentityState(isSupported: true, name: shortcut.name);
    return const NativeOperationResult('applied');
  }

  @override
  Future<NativeInspection> inspect(List<NativeVariantSpec> variants) async {
    calls.add('inspect:${variants.map((v) => v.id).join(',')}');
    return NativeInspection(issues: inspectionIssues, info: {'fake': true});
  }

  @override
  Future<Map<String, String>> loadSelection() async => {...savedSelection};

  @override
  Future<void> saveSelection(Map<String, String> selection) async {
    savedSelection = {...selection};
  }
}

/// An asset bundle with a fixed set of assets and a matching manifest.
class FakeAssetBundle extends AssetBundle {
  FakeAssetBundle(this.assets);

  final Set<String> assets;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage({
        for (final a in assets)
          a: [
            {'asset': a},
          ],
      })!;
    }
    if (!assets.contains(key)) throw FlutterError('Unable to load asset: $key');
    return ByteData.sublistView(Uint8List.fromList(key.codeUnits));
  }

  @override
  Future<T> loadStructuredData<T>(
    String key,
    Future<T> Function(String value) parser,
  ) async => parser(await loadString(key));
}

const demoConfig = IconShiftConfig(
  defaultIdentity: AppIdentity(
    name: 'My App',
    icon: AppIcon.asset('assets/default.png'),
    platforms: {
      IconShiftPlatform.android: IdentityOverride(
        icon: AppIcon.asset('assets/android.png'),
      ),
    },
  ),
  variants: {
    'dark': AppIdentity(
      name: 'My App Dark',
      icon: AppIcon.asset('assets/dark.png'),
    ),
    'blue': AppIdentity(icon: AppIcon.asset('assets/blue.png')),
    'pro': AppIdentity(name: 'My App Pro'),
  },
);

const demoAssets = {
  'assets/default.png',
  'assets/android.png',
  'assets/dark.png',
  'assets/blue.png',
};
