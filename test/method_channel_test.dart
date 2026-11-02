import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_shift/icon_shift.dart';
import 'package:icon_shift/icon_shift_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelIconShift();
  const channel = MethodChannel('icon_shift');
  final calls = <MethodCall>[];
  Object? Function(MethodCall call) reply = (_) => null;

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return reply(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('MethodChannelIconShift is the default instance', () {
    expect(IconShiftPlatformInterface.instance, isA<MethodChannelIconShift>());
  });

  test('getCapabilities parses the native map', () async {
    reply = (_) => {
      'icon': {
        'supported': true,
        'scope': 'launcher',
        'persistsNatively': true,
        'requiresPreconfiguredResources': true,
      },
      'displayName': {
        'supported': false,
        'scope': 'none',
        'limitation': 'nope',
      },
      'iconAndNameLinked': true,
      'notes': ['a note'],
    };
    final caps = await platform.getCapabilities();
    expect(caps.icon.scope, IdentityScope.launcher);
    expect(caps.icon.persistsNatively, isTrue);
    expect(caps.requiresPreconfiguredResources, isTrue);
    expect(caps.canChangeDisplayName, isFalse);
    expect(caps.displayName.limitation, 'nope');
    expect(caps.iconAndNameLinked, isTrue);
    expect(caps.notes, ['a note']);
  });

  test('unknown scope strings degrade to none', () {
    final cap = OperationCapability.fromMap({'supported': true, 'scope': '?'});
    expect(cap.scope, IdentityScope.none);
    expect(OperationCapability.fromMap(cap.toMap()), cap);
  });

  test('setIcon sends key and bytes, parses the result', () async {
    reply = (_) => {'status': 'applied', 'displayName': 'Label'};
    final result = await platform.setIcon(
      NativeIconRequest(key: 'dark', bytes: Uint8List.fromList([1, 2])),
    );
    expect(calls.single.method, 'setIcon');
    expect(calls.single.arguments, {
      'key': 'dark',
      'bytes': Uint8List.fromList([1, 2]),
    });
    expect(result.status, 'applied');
    expect(result.displayName, 'Label');
  });

  test('native errors surface as PlatformException', () async {
    reply = (_) => throw PlatformException(code: 'missing_resource');
    await expectLater(
      platform.setIcon(const NativeIconRequest(key: 'x')),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'missing_resource',
        ),
      ),
    );
  });

  test('setDisplayName, state, inspect and selection round-trip', () async {
    reply = (call) => switch (call.method) {
      'setDisplayName' => {'status': 'unchanged'},
      'getNativeState' => {'iconKey': 'dark', 'displayName': 'D'},
      'inspect' => {
        'issues': [
          {
            'severity': 'error',
            'code': 'missing_alias',
            'message': 'm',
            'variantId': 'dark',
          },
        ],
        'info': {'sdkInt': 34},
      },
      'loadSelection' => {'icon': 'dark'},
      _ => null,
    };
    expect((await platform.setDisplayName(null)).status, 'unchanged');
    expect(calls.last.arguments, {'name': null});

    final state = await platform.getNativeState();
    expect(state.iconKey, 'dark');
    expect(state.displayName, 'D');

    final inspection = await platform.inspect(const [
      NativeVariantSpec(id: 'dark', hasOwnIcon: true, name: 'D'),
    ]);
    expect(calls.last.arguments, {
      'variants': [
        {'id': 'dark', 'hasOwnIcon': true, 'name': 'D'},
      ],
    });
    expect(inspection.issues.single.severity, ValidationSeverity.error);
    expect(inspection.issues.single.variantId, 'dark');
    expect(inspection.info, {'sdkInt': 34});

    expect(await platform.loadSelection(), {'icon': 'dark'});
    await platform.saveSelection({'icon': 'blue'});
    expect(calls.last.arguments, {
      'selection': {'icon': 'blue'},
    });
  });
}
