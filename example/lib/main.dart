import 'package:flutter/material.dart';
import 'package:icon_shift/icon_shift.dart';

// Generated from icon_shift.yaml by `dart run icon_shift_generator`. It
// shows the main idea: one shared default icon/name, overridden for Android
// (icon and label) and web (favicon), plus three variants.
import 'icon_shift_config.g.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? initError;
  try {
    await IconShift.initialize(iconShiftConfig);
  } on IconShiftException catch (e) {
    initError = e;
  }
  runApp(DemoApp(initError: initError));
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key, this.initError});

  final Object? initError;

  @override
  Widget build(BuildContext context) {
    // MaterialApp.title becomes the Android recent-apps label and the web
    // document title on every rebuild; following IconShift keeps it from
    // undoing setDisplayName / setIdentity.
    return ValueListenableBuilder<String?>(
      valueListenable: IconShift.displayNameListenable,
      builder: (context, name, _) => MaterialApp(
        title: name ?? iconShiftConfig.defaultIdentity.name ?? 'IconShift',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: initError != null
            ? Scaffold(
                body: Center(child: Text('IconShift failed: $initError')),
              )
            : const DemoPage(),
      ),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  IconShiftCapabilities? _capabilities;
  IconShiftState? _state;
  List<IdentityVariant> _variants = const [];
  IconShiftValidationResult? _validation;
  IconShiftDiagnostics? _diagnostics;
  ApplicationInfo? _info;
  PlatformCapabilities? _platformCapabilities;
  IconShiftResult? _lastResult;
  ShortcutIdentityState? _shortcut;
  String? _batchIcon;
  bool _busy = false;
  final _name = TextEditingController(text: 'My Custom Name');
  final _remoteUrl = TextEditingController(
    text: 'https://example.com/icon_shift/remote_icon.json',
  );

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _name.dispose();
    _remoteUrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final capabilities = await IconShift.getCapabilities();
    final state = await IconShift.getCurrentIdentity();
    final variants = await IconShift.getVariants();
    final validation = await IconShift.validateConfiguration();
    final diagnostics = await IconShift.getDiagnostics();
    final info = await IconShift.getApplicationInfo();
    final platformCapabilities = await IconShift.getPlatformCapabilities();
    final shortcut = await IconShift.getShortcutIdentity();
    if (!mounted) return;
    setState(() {
      _capabilities = capabilities;
      _state = state;
      _variants = variants;
      _validation = validation;
      _diagnostics = diagnostics;
      _info = info;
      _platformCapabilities = platformCapabilities;
      _shortcut = shortcut;
    });
  }

  Future<void> _run(Future<IconShiftResult> Function() action) async {
    setState(() => _busy = true);
    try {
      final result = await action();
      setState(() => _lastResult = result);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_summary(result))));
      }
    } on IconShiftException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Says what the user will see, not the enum names: "unchanged" means the
  /// value is already in effect, which reads like failure otherwise.
  String _summary(IconShiftResult r) {
    String? part(String what, OperationOutcome o) => switch (o.status) {
      OperationStatus.applied => '$what applied',
      OperationStatus.pending => '$what: waiting for the user or the OS',
      OperationStatus.unchanged => '$what already in effect',
      OperationStatus.skipped => '$what skipped',
      OperationStatus.unsupported => '$what not possible on this platform',
      OperationStatus.failed => '$what failed',
      OperationStatus.notRequested => null,
    };
    final parts = [?part('Icon', r.icon), ?part('Name', r.displayName)];
    final lines = [
      if (parts.isEmpty) 'Nothing to change' else parts.join(' · '),
      // The OS's own words: where it shows, or why it could not.
      ?r.icon.message,
      if (r.displayName.message != r.icon.message) ?r.displayName.message,
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final caps = _capabilities;
    return Scaffold(
      appBar: AppBar(
        title: const Text('IconShift demo'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: caps == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _capabilitiesCard(caps),
                  _applicationInfoCard(),
                  _propertiesCard(),
                  _stateCard(),
                  _variantsCard(caps),
                  _customCard(caps),
                  _remoteCard(),
                  _shortcutCard(caps),
                  if (_lastResult != null) _resultCard(_lastResult!),
                  _validationCard(),
                  _diagnosticsCard(),
                ],
              ),
            ),
    );
  }

  Widget _section(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );

  Widget _capabilitiesCard(IconShiftCapabilities caps) => _section(
    'Capabilities (${caps.platform?.name ?? 'unsupported platform'})',
    [
      _capabilityRow('Icon', caps.icon),
      _capabilityRow('Display name', caps.displayName),
      if (caps.iconAndNameLinked)
        const Text('Icon and name are linked: each variant switches both.'),
      for (final note in caps.notes) Text('• $note'),
    ],
  );

  Widget _capabilityRow(String label, OperationCapability c) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      c.isSupported ? Icons.check_circle : Icons.block,
      color: c.isSupported ? Colors.green : Colors.grey,
    ),
    title: Text('$label: ${c.isSupported ? c.scope.name : 'not supported'}'),
    subtitle: Text(
      [
        if (c.persistsNatively) 'persists across restarts',
        if (!c.persistsNatively && c.isSupported) 're-applied on launch',
        if (c.requiresPreconfiguredResources) 'preconfigured variants only',
        if (c.acceptsArbitraryValues) 'any value',
        ?c.limitation,
      ].join(' · '),
    ),
  );

  /// Where a runtime name change is actually visible on this platform.
  static String _whereNameShows(IdentityScope scope) => switch (scope) {
    IdentityScope.launcher => 'Launcher',
    IdentityScope.taskSwitcher => 'Recent apps',
    IdentityScope.windowTitle => 'Window title',
    IdentityScope.browserTab => 'Browser tab',
    IdentityScope.launcherShortcut => 'Home-screen shortcut',
    IdentityScope.runningApp => 'Dock / taskbar',
    IdentityScope.none => 'Nowhere',
  };

  Widget _stateCard() {
    final s = _state;
    final caps = _capabilities;
    if (s == null || caps == null) return const SizedBox.shrink();
    final launcherName = _variants
        .where((v) => v.isCurrentIcon)
        .map((v) => v.displayName)
        .firstOrNull;
    return _section('Current identity', [
      // The two names are different things on Android; spell out which is
      // which so "unchanged" is never a mystery.
      if (caps.iconAndNameLinked && launcherName != null)
        Text('Launcher (compiled in): $launcherName'),
      Text(
        '${_whereNameShows(caps.displayName.scope)} (runtime): '
        '${s.nativeDisplayName ?? 'unknown'}',
      ),
      if (_shortcut?.isPinned ?? false)
        Text('Home-screen shortcut: ${_shortcut!.name}'),
      const SizedBox(height: 4),
      Text(
        'Requested: identity=${s.requestedIdentity ?? '-'}, '
        'icon=${s.requestedIconVariant ?? 'default'}, '
        'name=${s.requestedDisplayName ?? '(shipped)'}',
      ),
      Text('Icon reported by the OS: ${s.nativeIconVariant ?? 'unknown'}'),
      if (!s.isIconInSync || !s.isDisplayNameInSync)
        const Text(
          'The OS reports something different from the request.',
          style: TextStyle(color: Colors.orange),
        ),
    ]);
  }

  Widget _variantsCard(IconShiftCapabilities caps) => _section('Variants', [
    for (final v in _variants)
      ListTile(
        key: ValueKey('variant-${v.id}'),
        contentPadding: EdgeInsets.zero,
        leading: v.previewIcon == null
            ? const Icon(Icons.image_not_supported)
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  v.previewIcon!.assetKey,
                  width: 40,
                  height: 40,
                ),
              ),
        title: Text(
          '${v.id}${v.isDefault ? ' (default)' : ''}'
          '${v.isCurrentIcon ? '  ✓' : ''}',
        ),
        subtitle: Text(
          v.isAvailable
              ? (v.displayName ?? '(no name)')
              : 'Unavailable: ${v.unavailableReason}',
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              key: ValueKey('preview-${v.id}'),
              tooltip: 'Preview',
              icon: const Icon(Icons.visibility),
              onPressed: () => _showPreview(v.id),
            ),
            IconButton(
              key: ValueKey('identity-${v.id}'),
              tooltip: 'Apply icon and name',
              icon: const Icon(Icons.badge),
              onPressed: v.isAvailable && !_busy
                  ? () => _run(() => IconShift.setIdentity(v.id))
                  : null,
            ),
            if (!caps.iconAndNameLinked)
              IconButton(
                key: ValueKey('icon-${v.id}'),
                tooltip: 'Apply icon only',
                icon: const Icon(Icons.image),
                onPressed: v.isAvailable && !_busy
                    ? () => _run(() => IconShift.setIcon(v.id))
                    : null,
              ),
          ],
        ),
      ),
    const SizedBox(height: 8),
    FilledButton.tonalIcon(
      key: const ValueKey('restore'),
      onPressed: _busy ? null : () => _run(IconShift.restoreDefault),
      icon: const Icon(Icons.restore),
      label: const Text('Restore default'),
    ),
  ]);

  Widget _customCard(IconShiftCapabilities caps) {
    final canName = caps.displayName.acceptsArbitraryValues;
    return _section('Custom name / combined update', [
      if (caps.iconAndNameLinked)
        Text(
          'Android launcher names: '
          '${_variants.map((v) => v.displayName).whereType<String>().toSet().join(', ')}. '
          'Typing one of them switches the launcher label; any other name '
          'appears only in the recent-apps screen.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      if (!canName)
        Text(
          'This platform cannot show an arbitrary display name; the buttons '
          'below demonstrate the "unsupported" result.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      TextField(
        key: const ValueKey('name-field'),
        controller: _name,
        decoration: const InputDecoration(labelText: 'Display name'),
      ),
      const SizedBox(height: 8),
      DropdownButton<String?>(
        value: _batchIcon,
        hint: const Text('Icon for combined update'),
        items: [
          const DropdownMenuItem(value: null, child: Text('(keep icon)')),
          for (final id in IconShift.config.variantIds)
            DropdownMenuItem(value: id, child: Text(id)),
        ],
        onChanged: (v) => setState(() => _batchIcon = v),
      ),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            key: const ValueKey('set-name'),
            onPressed: _busy
                ? null
                : () => _run(() => IconShift.setDisplayName(_name.text)),
            child: Text(
              caps.iconAndNameLinked ? 'Set name (recents only)' : 'Set name',
            ),
          ),
          OutlinedButton(
            key: const ValueKey('set-both'),
            onPressed: _busy
                ? null
                : () => _run(
                    () => IconShift.setCustomIdentity(
                      iconVariant: _batchIcon,
                      displayName: _name.text,
                    ),
                  ),
            child: const Text('Set icon + name'),
          ),
        ],
      ),
    ]);
  }

  /// A server publishes RemoteIcon JSON (icon + dark/tinted/clear URLs and
  /// an optional bundled variant for iOS/Android).
  Widget _remoteCard() => _section('Remote icon (from a server)', [
    TextField(
      key: const ValueKey('remote-url'),
      controller: _remoteUrl,
      decoration: const InputDecoration(labelText: 'RemoteIcon JSON URL'),
    ),
    const SizedBox(height: 8),
    OutlinedButton(
      key: const ValueKey('apply-remote'),
      onPressed: _busy
          ? null
          : () => _run(() async {
              final icon = await IconShift.fetchRemoteIcon(
                Uri.parse(_remoteUrl.text.trim()),
              );
              return IconShift.setRemoteIcon(icon);
            }),
      child: const Text('Download and apply'),
    ),
  ]);

  /// Any name and any icon, on every platform that allows it at all. On
  /// Android this is a home-screen shortcut: the only launcher entry whose
  /// name and image are not compiled into the build.
  Widget _shortcutCard(IconShiftCapabilities caps) {
    final state = _shortcut;
    return _section('Any name + icon (setArbitraryIdentity)', [
      Text(
        caps.canShowArbitraryIdentity
            ? 'Uses the name typed above and the icon picked for the '
                  'combined update.'
            : 'This platform cannot show a name chosen at runtime anywhere.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      if (caps.shortcut.limitation case final limitation?)
        Text(limitation, style: Theme.of(context).textTheme.bodySmall),
      if (state != null)
        Text(
          'Shortcut: ${state.isPinned
              ? 'on the home screen as "${state.name}"'
              : state.isSupported
              ? 'not placed yet'
              : 'unavailable'}',
        ),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            key: const ValueKey('set-anywhere'),
            onPressed: _busy
                ? null
                : () => _run(
                    () => IconShift.setArbitraryIdentity(
                      name: _name.text,
                      variant: _batchIcon,
                    ),
                  ),
            child: const Text('Apply name + icon'),
          ),
          if (state?.isPinned ?? false)
            OutlinedButton(
              key: const ValueKey('remove-shortcut'),
              onPressed: _busy
                  ? null
                  : () => _run(IconShift.removeShortcutIdentity),
              child: const Text('Disable shortcut'),
            ),
        ],
      ),
    ]);
  }

  Widget _resultCard(IconShiftResult r) => _section('Last result', [
    Text('Icon: ${r.icon}'),
    Text('Display name: ${r.displayName}'),
    Text(
      'complete: ${r.isComplete} · partial: ${r.isPartial} · '
      'failures: ${r.hasFailures}',
    ),
  ]);

  Widget _validationCard() {
    final v = _validation;
    if (v == null) return const SizedBox.shrink();
    return _section('Validation', [
      if (v.issues.isEmpty) const Text('No issues.'),
      for (final issue in v.issues)
        Text(
          '${issue.severity.name}: ${issue.message}',
          style: TextStyle(
            color: switch (issue.severity) {
              ValidationSeverity.error => Colors.red,
              ValidationSeverity.warning => Colors.orange,
              ValidationSeverity.info => null,
            },
          ),
        ),
    ]);
  }

  Widget _applicationInfoCard() {
    final i = _info;
    if (i == null) return const SizedBox.shrink();
    return _section('Application info (from the OS)', [
      Text('Display name: ${i.displayName ?? '(not exposed)'}'),
      Text('Application id: ${i.applicationId ?? '(not exposed)'}'),
      Text('Version: ${i.version ?? '?'}+${i.buildNumber ?? '?'}'),
      if (i.executableName != null) Text('Executable: ${i.executableName}'),
      Text('Installed as: ${i.installationType.name}'),
      Text('Current icon: ${i.currentIconVariant ?? 'unknown'}'),
    ]);
  }

  Widget _propertiesCard() {
    final c = _platformCapabilities;
    if (c == null) return const SizedBox.shrink();
    String names(List<IdentityProperty> p) =>
        p.isEmpty ? '—' : p.map((e) => e.name).join(', ');
    return _section('Identity properties on ${c.platform?.name ?? '?'}', [
      Text('Runtime: ${names(c.runtimeChangeable)}'),
      Text('Build time only: ${names(c.buildTimeOnly)}'),
      Text('Needs a new install: ${names(c.requiringReinstall)}'),
      for (final line in c.requiredConfiguration) Text('Setup: $line'),
    ]);
  }

  Future<void> _showPreview(String id) async {
    final preview = await IconShift.previewIdentity(id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Preview "$id"'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final MapEntry(:key, :value) in preview.platforms.entries)
                Text(
                  '${key.name}${key == preview.currentPlatform ? ' (this device)' : ''}: $value',
                ),
              for (final w in preview.warnings)
                Text('${w.severity.name}: ${w.message}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _diagnosticsCard() => _section('Diagnostics', [
    SelectableText(
      _diagnostics?.toReport() ?? '…',
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    ),
  ]);
}
