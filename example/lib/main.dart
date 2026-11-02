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

class DemoApp extends StatefulWidget {
  const DemoApp({super.key, this.initError});

  final Object? initError;

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  // On web, MaterialApp.title writes document.title on rebuild; keep it in
  // sync with IconShift so it does not undo setDisplayName.
  String _title = iconShiftConfig.defaultIdentity.name ?? 'IconShift';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: _title,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: widget.initError != null
          ? Scaffold(
              body: Center(
                child: Text('IconShift failed: ${widget.initError}'),
              ),
            )
          : DemoPage(onTitle: (t) => setState(() => _title = t)),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key, required this.onTitle});

  final ValueChanged<String> onTitle;

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  IconShiftCapabilities? _capabilities;
  IconShiftState? _state;
  List<IdentityVariant> _variants = const [];
  IconShiftValidationResult? _validation;
  IconShiftDiagnostics? _diagnostics;
  IconShiftResult? _lastResult;
  String? _batchIcon;
  bool _busy = false;
  final _name = TextEditingController(text: 'My Custom Name');

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final capabilities = await IconShift.getCapabilities();
    final state = await IconShift.getCurrentIdentity();
    final variants = await IconShift.getVariants();
    final validation = await IconShift.validateConfiguration();
    final diagnostics = await IconShift.getDiagnostics();
    if (!mounted) return;
    setState(() {
      _capabilities = capabilities;
      _state = state;
      _variants = variants;
      _validation = validation;
      _diagnostics = diagnostics;
    });
    final native = state.nativeDisplayName;
    if (native != null &&
        capabilities.displayName.scope == IdentityScope.browserTab) {
      widget.onTitle(native);
    }
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

  static String _summary(IconShiftResult r) => r.isComplete
      ? 'Done: icon ${r.icon.status.name}, name ${r.displayName.status.name}'
      : r.hasFailures
      ? 'Failed: ${r.icon.message ?? r.displayName.message}'
      : 'Partly applied: icon ${r.icon.status.name}, name ${r.displayName.status.name}';

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
                  _stateCard(),
                  _variantsCard(caps),
                  _customCard(caps),
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

  Widget _stateCard() {
    final s = _state;
    if (s == null) return const SizedBox.shrink();
    return _section('Current identity', [
      Text(
        'Requested: identity=${s.requestedIdentity ?? '-'}, '
        'icon=${s.requestedIconVariant ?? 'default'}, '
        'name=${s.requestedDisplayName ?? '(shipped)'}',
      ),
      Text(
        'Reported by the OS: icon=${s.nativeIconVariant ?? 'unknown'}, '
        'name=${s.nativeDisplayName ?? 'unknown'}',
      ),
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
            child: const Text('Set name'),
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

  Widget _diagnosticsCard() => _section('Diagnostics', [
    SelectableText(
      _diagnostics?.toReport() ?? '…',
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    ),
  ]);
}
