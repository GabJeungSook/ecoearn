import 'package:flutter/material.dart';

import '../data/deposit_recorder.dart';
import '../data/student_repository.dart';
import '../serial/device_event.dart';
import '../serial/auto_connect.dart';
import '../serial/serial_connection.dart';
import '../serial/simulator.dart';
import '../theme/app_theme.dart';
import '../widgets/page_parts.dart';
import '../widgets/stat_card.dart';
import 'live_session.dart';
import 'scale_dialog.dart';
import 'stages.dart';

const _rejectLabels = {
  'bin_full': 'bin is full',
  'mechanism': 'machine error',
  'no_item': 'no bottle detected',
  'too_heavy': 'too heavy',
};

const _detailLabels = {
  'scale_not_calibrated': 'scale not calibrated',
  'scale_not_answering': 'scale not answering, check the HX711 wires',
  'scale_unsettled': 'weight never settled, keep hands off the scale',
};

String _grams(double g) => g == g.roundToDouble() ? '${g.toInt()} g' : '${g.toStringAsFixed(1)} g';

String _time(DateTime t) =>
    [t.hour, t.minute, t.second].map((n) => n.toString().padLeft(2, '0')).join(':');

String _plainUid(String uid) => uid;

/// [who] turns a card UID into how the student is shown, e.g. "Juan Dela Cruz (A3F29B11)".
String describeEvent(DeviceEvent event, [String Function(String uid) who = _plainUid]) => switch (event) {
      BootEvent(simulated: true) => 'Demo mode: simulated machine started',
      BootEvent(:final version) => 'ESP32 started (firmware $version)',
      CardEvent(:final uid) => 'Card tapped: ${who(uid)}',
      ScanEvent(:final uid) => 'Card read for registration: ${who(uid)}',
      StageEvent(:final uid, :final stage) => 'Machine step: $stage (${who(uid)})',
      WeightEvent(:final uid, :final grams, :final points) =>
        'Deposit: ${who(uid)}, ${_grams(grams)} → $points ${points == 1 ? 'point' : 'points'}',
      RejectEvent(:final uid, :final reason, :final grams, :final detail) =>
        'Rejected: ${who(uid)}, ${_rejectLabels[reason] ?? reason}'
            '${detail == null ? '' : ' (${_detailLabels[detail] ?? detail})'}'
            '${grams > 0 ? ' (${_grams(grams)})' : ''}',
      BinEvent(:final level) => 'Bin level: $level%',
      UnknownEvent(:final raw) => 'Unrecognized message: $raw',
    };

IconData _icon(DeviceEvent event) => switch (event) {
      BootEvent() => Icons.power_settings_new,
      CardEvent() => Icons.contactless,
      ScanEvent() => Icons.badge_outlined,
      StageEvent() => Icons.settings_outlined,
      WeightEvent() => Icons.scale,
      RejectEvent() => Icons.block,
      BinEvent() => Icons.delete_outline,
      UnknownEvent() => Icons.help_outline,
    };

Color _eventColor(DeviceEvent event) => switch (event) {
      BootEvent() => EcoColors.muted,
      CardEvent() || ScanEvent() || StageEvent() => EcoColors.sky,
      WeightEvent() => EcoColors.emerald,
      RejectEvent() => EcoColors.coral,
      BinEvent() => EcoColors.amber,
      UnknownEvent() => EcoColors.muted,
    };

class LiveScreen extends StatefulWidget {
  const LiveScreen({
    super.key,
    required this.connection,
    required this.session,
    required this.students,
    required this.recorder,
    required this.simulator,
    required this.autoConnect,
  });

  final SerialConnection connection;
  final LiveSession session;
  final StudentRepository students;
  final DepositRecorder recorder;
  final Simulator simulator;
  final AutoConnect autoConnect;

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
    List<PortInfo> ports;
    try {
      ports = SerialConnection.listPorts();
    } catch (e) {
      ports = const []; // serial library unavailable; the dropdown shows "No ports found"
    }
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
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.connection, widget.session, widget.students, widget.recorder, widget.simulator]),
        builder: (context, _) {
          final connection = widget.connection;
          final firmware = widget.session.firmwareVersion;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                overline: widget.simulator.running
                    ? '● Demo mode: simulated machine, nothing is saved'
                    : connection.isConnected
                        ? '● Connected to ${connection.portName}${firmware == null ? '' : ' · firmware $firmware'}'
                        : '○ Not connected',
                title: 'Live',
                actions: _connectionActions(),
              ),
              for (final error in [connection.error, widget.recorder.error])
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 12),
                    child: Text(error, style: const TextStyle(color: EcoColors.coral)),
                  ),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 26), child: _statusCards(context)),
              const Padding(padding: EdgeInsets.fromLTRB(32, 28, 32, 10), child: SmallLabel('Event log')),
              Expanded(child: _eventLog(context)),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _connectionActions() {
    final connection = widget.connection;
    final connected = connection.isConnected;
    return [
      Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: EcoColors.field, borderRadius: BorderRadius.circular(10)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedPort,
            hint: const Text('No ports found'),
            borderRadius: BorderRadius.circular(12),
            onChanged: connected ? null : (name) => setState(() => _selectedPort = name),
            items: [
              for (final p in _ports) DropdownMenuItem(value: p.name, child: Text(p.description)),
            ],
          ),
        ),
      ),
      SquareIconButton(icon: Icons.refresh, tooltip: 'Refresh port list', onPressed: connected ? null : _refreshPorts),
      SizedBox(
        height: 40,
        child: connected
            ? OutlinedButton(
                onPressed: () {
                  widget.autoConnect.pause(); // stay disconnected until Connect is clicked
                  connection.disconnect();
                },
                child: const Text('Disconnect'),
              )
            : FilledButton(
                onPressed: _selectedPort == null
                    ? null
                    : () {
                        widget.autoConnect.resume();
                        connection.connect(_selectedPort!);
                      },
                child: const Text('Connect'),
              ),
      ),
      SquareIconButton(
        icon: Icons.scale_outlined,
        tooltip: connected ? 'Calibrate the scale' : 'Connect to the machine to calibrate the scale',
        onPressed: connected && !widget.simulator.running
            ? () => showDialog<void>(context: context, builder: (_) => ScaleDialog(connection: connection))
            : null,
      ),
      _DemoButton(simulator: widget.simulator),
      SquareIconButton(icon: Icons.clear_all, tooltip: 'Clear the log', onPressed: widget.session.clear),
    ];
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
        StatCard(
          icon: Icons.contactless,
          label: 'Current student',
          value: processingUid == null
              ? '—'
              : widget.students.byUid(processingUid)?.name ?? 'Unregistered card',
          detail: processingUid == null
              ? 'Waiting for a card tap'
              : '$processingUid · ${MachineStage.of(session.stage)?.message ?? 'Processing bottle'}…',
          valueColor: processingUid != null && widget.students.byUid(processingUid) == null ? EcoColors.amber : null,
          highlight: true,
          loading: processingUid != null,
        ),
        StatCard(
          icon: Icons.scale,
          label: 'Last bottle',
          value: lastTitle,
          detail: lastSubtitle,
          color: EcoColors.sky,
          valueColor: session.lastResult is RejectEvent ? colors.error : null,
        ),
        StatCard(
          icon: Icons.delete_outline,
          label: 'Bin level',
          value: binLevel == null ? '—' : '$binLevel%',
          detail: binFull ? 'Full — please empty' : 'OK',
          color: EcoColors.amber,
          valueColor: binFull ? colors.error : null,
          progress: binLevel == null ? null : binLevel / 100,
        ),
        StatCard(
          icon: Icons.eco,
          color: EcoColors.teal,
          label: 'This session',
          value: '${session.points} pts',
          detail: '${session.bottles} ${session.bottles == 1 ? 'bottle' : 'bottles'} · ${session.rejects} rejected',
        ),
      ],
    );
  }

  Widget _eventLog(BuildContext context) {
    final log = widget.session.log;
    if (log.isEmpty) {
      return EmptyState(
        icon: Icons.sensors,
        message: widget.connection.isConnected
            ? 'Connected. Waiting for messages from the ESP32…'
            : 'Connect to the ESP32 to see live events.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
      itemCount: log.length,
      itemBuilder: (context, i) {
        final event = log[i];
        return RowCard(
          child: Row(children: [
            IconBadge(icon: _icon(event), color: _eventColor(event), size: 32),
            const SizedBox(width: 14),
            Expanded(child: Text(describeEvent(event, _who), style: const TextStyle(fontWeight: FontWeight.w500))),
            if (event.simulated)
              Container(
                margin: const EdgeInsets.only(right: 14),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: EcoColors.sky.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'DEMO',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: EcoColors.sky),
                ),
              ),
            Text(_time(event.receivedAt), style: const TextStyle(color: EcoColors.muted, fontSize: 13)),
          ]),
        );
      },
    );
  }
}

/// Starts or stops demo mode: simulated deposits, so the screens can be shown
/// without an ESP32. Nothing it does is saved.
class _DemoButton extends StatelessWidget {
  const _DemoButton({required this.simulator});

  final Simulator simulator;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: simulator.running
            ? 'Stop the simulated deposits'
            : 'Simulate deposits without an ESP32 (nothing is saved)',
        child: SizedBox(
          height: 40,
          child: simulator.running
              ? FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: EcoColors.sky),
                  onPressed: simulator.stop,
                  icon: const Icon(Icons.stop_rounded, size: 20),
                  label: const Text('Stop demo'),
                )
              : OutlinedButton.icon(
                  onPressed: simulator.start,
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('Demo'),
                ),
        ),
      );
}
