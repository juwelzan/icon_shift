import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'src/config/platform.dart';
import 'src/models/application_info.dart';
import 'src/models/capabilities.dart';
import 'src/models/validation.dart';
import 'src/platform/icon_shift_platform_interface.dart';

/// Web implementation of IconShift: favicon and `document.title`.
///
/// The installed-PWA launcher icon and name come from `manifest.json`, which
/// browsers read at install time; they cannot be changed per user at runtime
/// and are not touched.
class IconShiftWeb extends IconShiftPlatformInterface {
  IconShiftWeb({web.Document? document, web.Storage? storage})
    : _document = document ?? web.document,
      _storageOverride = storage;

  static void registerWith(Registrar registrar) {
    IconShiftPlatformInterface.instance = IconShiftWeb();
  }

  static const storageKey = 'icon_shift.selection';

  /// Marks the favicon link IconShift inserted.
  static const _ownedAttribute = 'data-icon-shift';

  final web.Document _document;
  final web.Storage? _storageOverride;

  String? _iconKey;

  /// Favicon links present before the first change, restored by
  /// [setIcon] with [defaultIconKey].
  List<web.Element>? _originalIcons;
  String? _originalTitle;

  /// `<meta name="theme-color">` content before the first change; `''` when
  /// the page had none.
  String? _originalThemeColor;

  web.Storage? get _localStorage {
    try {
      return _storageOverride ?? web.window.localStorage;
    } on Object {
      return null; // Storage disabled (e.g. some private modes).
    }
  }

  @override
  Future<IconShiftCapabilities> getCapabilities() async =>
      const IconShiftCapabilities(
        platform: IconShiftPlatform.web,
        icon: OperationCapability(
          isSupported: true,
          scope: IdentityScope.browserTab,
          acceptsArbitraryValues: true,
          limitation:
              'Changes the browser-tab favicon only. The icon of an installed '
              'PWA comes from manifest.json and cannot change at runtime.',
        ),
        displayName: OperationCapability(
          isSupported: true,
          scope: IdentityScope.browserTab,
          acceptsArbitraryValues: true,
          limitation:
              'Changes document.title. The name of an installed PWA comes '
              'from manifest.json. MaterialApp.title also writes '
              'document.title when it rebuilds.',
        ),
        notes: [
          'Safari may not update a favicon changed after page load.',
          'Theme colors (AppIdentity.themeColor) are applied to '
              '<meta name="theme-color">.',
        ],
      );

  @override
  Future<NativeIdentityState> getNativeState() async => NativeIdentityState(
    iconKey: _iconKey ?? defaultIconKey,
    displayName: _document.title,
  );

  @override
  Future<NativeOperationResult> setIcon(NativeIconRequest request) async {
    final head = _document.head;
    if (head == null) {
      throw PlatformException(
        code: NativeErrorCodes.nativeFailure,
        message: 'The document has no <head> element.',
      );
    }
    if (request.key == (_iconKey ?? defaultIconKey)) {
      return const NativeOperationResult('unchanged');
    }

    final current = _iconLinks();
    _originalIcons ??= [
      for (final link in current)
        if (!link.hasAttribute(_ownedAttribute)) link,
    ];
    for (final link in current) {
      link.remove();
    }

    if (request.key == defaultIconKey) {
      for (final link in _originalIcons!) {
        head.append(link);
      }
      _iconKey = null;
      return const NativeOperationResult('applied');
    }

    final assetKey = request.assetKey;
    final remote = request.url;
    if (assetKey == null && remote == null) {
      throw PlatformException(
        code: NativeErrorCodes.invalidArgument,
        message: 'No icon asset for variant "${request.key}".',
      );
    }
    final link = _document.createElement('link') as web.HTMLLinkElement
      ..rel = 'icon'
      ..href = remote?.toString() ?? ui_web.assetManager.getAssetUrl(assetKey!)
      ..setAttribute(_ownedAttribute, request.key);
    final type = _mimeType(remote?.path ?? assetKey!);
    if (type != null) link.type = type;
    head.append(link);
    _iconKey = request.key;
    return const NativeOperationResult('applied');
  }

  @override
  Future<NativeOperationResult> setDisplayName(String? name) async {
    _originalTitle ??= _document.title;
    final target = name ?? _originalTitle!;
    if (_document.title == target) {
      return const NativeOperationResult('unchanged');
    }
    _document.title = target;
    return const NativeOperationResult('applied');
  }

  @override
  Future<NativeOperationResult> setThemeColor(int? argb) async {
    final head = _document.head;
    if (head == null) {
      throw PlatformException(
        code: NativeErrorCodes.nativeFailure,
        message: 'The document has no <head> element.',
      );
    }
    var meta =
        _document.querySelector('meta[name="theme-color"]')
            as web.HTMLMetaElement?;
    _originalThemeColor ??= meta?.content ?? '';
    final target = argb == null
        ? _originalThemeColor!
        : '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    if ((meta?.content ?? '') == target) {
      return const NativeOperationResult('unchanged');
    }
    if (target.isEmpty) {
      meta?.remove();
      return const NativeOperationResult('applied');
    }
    if (meta == null) {
      meta = _document.createElement('meta') as web.HTMLMetaElement
        ..name = 'theme-color';
      head.append(meta);
    }
    meta.content = target;
    return const NativeOperationResult('applied');
  }

  @override
  Future<ApplicationInfo> getApplicationInfo() async {
    final standalone = web.window
        .matchMedia('(display-mode: standalone)')
        .matches;
    var version = const <String, String>{};
    try {
      // Flutter writes version.json next to index.html.
      final response = await web.window
          .fetch('version.json'.toJS, web.RequestInit(cache: 'no-store'))
          .toDart;
      if (response.ok) {
        final json =
            jsonDecode((await response.text().toDart).toDart)
                as Map<String, Object?>;
        version = {
          if (json['version'] case final String v) 'version': v,
          if (json['build_number'] case final String b) 'buildNumber': b,
          if (json['app_name'] case final String n) 'appName': n,
        };
      }
    } on Object {
      // Not served (e.g. tests): version stays unknown.
    }
    return ApplicationInfo(
      platform: IconShiftPlatform.web,
      displayName: version['appName'],
      applicationId: web.window.location.origin,
      version: version['version'],
      buildNumber: version['buildNumber'],
      windowTitle: _document.title,
      installationType: standalone
          ? InstallationType.installedPwa
          : InstallationType.browser,
      osVersion: web.window.navigator.userAgent,
    );
  }

  @override
  Future<NativeInspection> inspect(List<NativeVariantSpec> variants) async {
    final standalone = web.window
        .matchMedia('(display-mode: standalone)')
        .matches;
    return NativeInspection(
      issues: [
        if (standalone)
          const ValidationIssue(
            severity: ValidationSeverity.info,
            code: 'installed_pwa',
            message:
                'Running as an installed PWA: the launcher icon and name come '
                'from manifest.json; only the window title and favicon '
                'change.',
            platform: IconShiftPlatform.web,
          ),
      ],
      info: {
        'displayModeStandalone': standalone,
        'faviconLinks': _iconLinks().length,
        'localStorageAvailable': _localStorage != null,
      },
    );
  }

  @override
  Future<Map<String, String>> loadSelection() async {
    final raw = _localStorage?.getItem(storageKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, Object?>).map(
        (k, v) => MapEntry(k, v as String),
      );
    } on Object {
      return {}; // Corrupt entry: start fresh.
    }
  }

  @override
  Future<void> saveSelection(Map<String, String> selection) async {
    final storage = _localStorage;
    if (storage == null) {
      throw PlatformException(
        code: NativeErrorCodes.nativeFailure,
        message: 'localStorage is not available.',
      );
    }
    if (selection.isEmpty) {
      storage.removeItem(storageKey);
    } else {
      storage.setItem(storageKey, jsonEncode(selection));
    }
  }

  List<web.Element> _iconLinks() {
    final nodes = _document.querySelectorAll('link[rel~="icon"]');
    return [
      for (var i = 0; i < nodes.length; i++) nodes.item(i)! as web.Element,
    ];
  }

  static String? _mimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.ico')) return 'image/x-icon';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return null;
  }
}
