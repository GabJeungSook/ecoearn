import 'package:flutter/material.dart';

import '../data/deposit_recorder.dart';
import '../data/student_repository.dart';
import '../serial/device_event.dart';
import '../serial/serial_connection.dart';
import 'live_session.dart';

const _rejectLabels = {
  'bin_full': 'bin is full',
  'mechanism': 'machine error',
  'no_item': 'no bottle detected',
  'too_heavy': 'too heavy',
};

String _grams(double g) => g == g.roundToDouble() ? '${g.toInt()} g' : '${g.toStringAsFixed(1)} g';

String _time(DateTime t) =>
    [t.hour, t.minute, t.second].map((n) => n.toString().padLeft(2, '0')).join(':');

String _plainUid(String uid) => uid;

/// [who] turns a card UID into how the student is shown, e.g. "Juan Dela Cruz (A3F29B11)".
String describeEvent(DeviceEvent event, [String Function(String uid) who = _plainUid]) => switch (event) {
      BootEvent(:final version) => 'ESP32 started (firmware $version)',
      CardEvent(:final uid) => 'Card tapped: ${who(uid)}',
      WeightEvent(:final uid, :final grams, :final points) =>
        'Deposit: ${who(uid)}, ${_grams(grams)} → $points ${points == 1 ? 'point' : 'points'}',
      RejectEvent(:final uid, :final reason, :final grams) =>
        'Rejected: ${who(uid)}, ${_rejectLabels[reason] ?? reason}'
            '${grams > 0 ? ' (${_grams(grams)})' : ''}',
      BinEvent(:final level) => 'Bin level: $level%',
      UnknownEvent(:final raw) => 'Unrecognized message: $raw',
    };

IconData _icon(DeviceEvent event) => switch (event) {
      BootEvent() => Icons.power_settings_new,
      CardEvent() => Icons.contactless,
      WeightEvent() => Icons.scale,
      RejectEvent() => Icons.block,
      BinEvent() => Icons.delete_outline,
      UnknownEvent() => Icons.help_outline,
    };

class LiveScreen extends StatefulWidget {
  const LiveScreen({
    super.key,
    required this.connection,
    required this.session,
    required this.students,
    required this.recorder,
  });

  final SerialConnection connection;
  final LiveSession session;
  final StudentRepository students;
  final DepositRecorder recorder;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  List<PortInfo> _ports = [];
  String? _selectedPort;

  @override
  void initState() {
    super.initState();
    _refreshPorts();
  }

  String _who(String uid) {
    final student = widget.students.byUid(uid);
    return student == null ? 'unregistered card $uid' : '${student.name} ($uid)';
  }

  void _refreshPorts() {
    final ports = SerialConnection.listPorts();
    setState(() {
      _ports = ports;
      if (!ports.any((p) => p.name == _selectedPort)) {
        _selectedPort = ports.where((p) => p.looksLikeEsp32).firstOrNull?.name ??
            ports.firstOrNull?.name;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EcoEarn — Live'),
        actions: [
          TextButton.icon(
            onPressed: widget.session.clear,
            icon: const Icon(Icons.clear_all),
            label: const Text('Clear'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.connection, widget.session, widget.students, widget.recorder]),
        builder: (context, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _connectionBar(context),
              const SizedBox(height: 16),
              _statusCards(context),
              const SizedBox(height: 16),
              Text('Event log', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Expanded(child: _eventLog(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _connectionBar(BuildContext context) {
    final connection = widget.connection;
    final colors = Theme.of(context).colorScheme;
    final connected = connection.isConnected;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('ESP32 port:'),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _selectedPort,
                  hint: const Text('No ports found'),
                  onChanged: connected ? null : (name) => setState(() => _selectedPort = name),
                  items: [
                    for (final p in _ports) DropdownMenuItem(value: p.name, child: Text(p.description)),
                  ],
                ),
                IconButton(
                  tooltip: 'Refresh port list',
                  onPressed: connected ? null : _refreshPorts,
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 8),
                if (connected)
                  OutlinedButton(onPressed: connection.disconnect, child: const Text('Disconnect'))
                else
                  FilledButton(
                    onPressed: _selectedPort == null ? null : () => connection.connect(_selectedPort!),
                    child: const Text('Connect'),
                  ),
                const Spacer(),
                Icon(Icons.circle, size: 12, color: connected ? Colors.green : colors.outline),
                const SizedBox(width: 6),
                Text(connected
                    ? 'Connected to ${connection.portName}'
                        '${widget.session.firmwareVersion == null ? '' : ' · firmware ${widget.session.firmwareVersion}'}'
                    : 'Not connected'),
              ],
            ),
            for (final error in [connection.error, widget.recorder.error])
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error, style: TextStyle(color: colors.error)),
              ],
          ],
        ),
      ),
    );
  }

  Widget _statusCards(BuildContext context) {
    final session = widget.session;
    final colors = Theme.of(context).colorScheme;

    final (lastTitle, lastSubtitle) = switch (session.lastResult) {
      WeightEvent(:final uid, :final grams, :final points) => ('${_grams(grams)} · $points pts', _who(uid)),
      RejectEvent(:final uid, :final reason) => ('Rejected', '${_who(uid)} · ${_rejectLabels[reason] ?? reason}'),
      _ => ('—', 'No bottles yet'),
    };
    final binLevel = session.binLevel;
    final binFull = binLevel != null && binLevel >= binFullPercent;
    final processingUid = session.processingUid;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatCard(
          icon: Icons.contactless,
          label: 'Current student',
          value: processingUid == null
              ? '—'
              : widget.students.byUid(processingUid)?.name ?? 'Unregistered card',
          detail: processingUid == null ? 'Waiting for a card tap' : '$processingUid · Processing bottle…',
          valueColor: processingUid != null && widget.students.byUid(processingUid) == null ? colors.error : null,
        ),
        _StatCard(icon: Icons.scale, label: 'Last bottle', value: lastTitle, detail: lastSubtitle),
        _StatCard(
          icon: Icons.delete_outline,
          label: 'Bin level',
          value: binLevel == null ? '—' : '$binLevel%',
          detail: binFull ? 'Full — please empty' : 'OK',
          valueColor: binFull ? colors.error : null,
          progress: binLevel == null ? null : binLevel / 100,
        ),
        _StatCard(
          icon: Icons.eco,
          label: 'This session',
          value: '${session.points} pts',
          detail: '${session.bottles} bottles · ${session.rejects} rejected',
        ),
      ],
    );
  }

  Widget _eventLog(BuildContext context) {
    final log = widget.session.log;
    if (log.isEmpty) {
      return Card(
        child: Center(
          child: Text(widget.connection.isConnected
              ? 'Connected. Waiting for messages from the ESP32…'
              : 'Connect to the ESP32 to see live events.'),
        ),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        itemCount: log.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final event = log[i];
          return ListTile(
            dense: true,
            leading: Icon(_icon(event), color: event is RejectEvent ? Theme.of(context).colorScheme.error : null),
            title: Text(describeEvent(event, _who)),
            trailing: Text(_time(event.receivedAt)),
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    this.valueColor,
    this.progress,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color? valueColor;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 18),
                const SizedBox(width: 6),
                Text(label, style: text.labelLarge),
              ]),
              const SizedBox(height: 8),
              Text(value, style: text.headlineSmall?.copyWith(color: valueColor)),
              if (progress != null) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(value: progress, color: valueColor),
              ],
              const SizedBox(height: 4),
              Text(detail, style: text.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
