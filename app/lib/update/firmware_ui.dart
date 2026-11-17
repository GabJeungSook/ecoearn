import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/stat_card.dart';
import 'firmware_updater.dart';

/// Explains the BOOT button once, then flashes.
Future<void> confirmAndFlash(BuildContext context, FirmwareUpdater updater) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Update the machine to firmware ${updater.bundledVersion}?'),
      content: const Text(
        'Takes about 30 seconds. Don\'t unplug the USB cable while it runs.\n\n'
        'When "Hold the BOOT button" appears, press and hold the BOOT button on the ESP32 '
        '(next to the USB port) until writing starts.\n\n'
        'The scale calibration and the points rate are kept.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Later')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Update machine')),
      ],
    ),
  );
  if (ok == true) await updater.flash();
}

/// Admin Settings card: the machine's firmware, the app's, and the update button with live steps.
class MachineFirmwareCard extends StatelessWidget {
  const MachineFirmwareCard({super.key, required this.updater});

  final FirmwareUpdater updater;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: updater,
        builder: (context, _) {
          final bundled = updater.bundledVersion;
          final machine = updater.machineVersion;
          final (String status, Color color) = switch (updater.state) {
            _ when bundled == null => ('This copy of EcoEarn carries no firmware (developer build).', EcoColors.muted),
            FlashState.preparing || FlashState.restarting => (updater.message ?? '', EcoColors.emerald),
            FlashState.waitingForBoot => (updater.message ?? '', EcoColors.amber),
            FlashState.writing => ('${updater.message} ${((updater.progress ?? 0) * 100).round()}%', EcoColors.emerald),
            FlashState.failed => (updater.message ?? 'The update failed.', EcoColors.coral),
            FlashState.done when !updater.updateAvailable => (updater.message ?? 'Updated.', EcoColors.emerald),
            _ when updater.updateAvailable => ('A firmware update is ready for the machine.', EcoColors.emerald),
            _ when machine == null => ('Connect the machine to check its firmware.', EcoColors.muted),
            _ => ('The machine is up to date.', EcoColors.muted),
          };
          return Container(
            constraints: const BoxConstraints(maxWidth: 720),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: EcoColors.line),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const IconBadge(icon: Icons.memory, color: EcoColors.emerald),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Machine firmware (ESP32)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      'Machine: ${machine ?? (updater.updateAvailable ? 'older version' : '—')}'
                      '   ·   In this app: ${bundled ?? '—'}',
                      style: const TextStyle(color: EcoColors.muted),
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: updater.updateAvailable ? () => confirmAndFlash(context, updater) : null,
                    icon: const Icon(Icons.system_update_alt, size: 18),
                    label: const Text('Update machine'),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                if (updater.busy) ...[
                  const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                ],
                Expanded(child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
              ]),
              if (updater.state == FlashState.writing) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(value: updater.progress, minHeight: 6),
              ],
            ]),
          );
        },
      );
}

/// Live screen banner while the connected machine needs a firmware update (or is being updated).
class FirmwareBanner extends StatelessWidget {
  const FirmwareBanner({super.key, required this.updater});

  final FirmwareUpdater updater;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: updater,
        builder: (context, _) {
          if (!updater.updateAvailable && !updater.busy) return const SizedBox.shrink();
          final writing = updater.state == FlashState.writing;
          return Container(
            margin: const EdgeInsets.fromLTRB(32, 0, 32, 16),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: updater.state == FlashState.waitingForBoot ? EcoColors.amber.withValues(alpha: 0.14) : EcoColors.mint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Icon(updater.busy ? Icons.downloading : Icons.memory, color: EcoColors.forest),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  updater.busy
                      ? '${updater.message}${writing ? ' ${((updater.progress ?? 0) * 100).round()}%' : ''}'
                      : 'Machine firmware ${updater.bundledVersion} is ready to install '
                          '(machine has ${updater.machineVersion ?? 'an older version'}).',
                  style: const TextStyle(color: EcoColors.forest, fontWeight: FontWeight.w600),
                ),
              ),
              if (!updater.busy)
                SizedBox(
                  height: 38,
                  child: FilledButton(
                    onPressed: () => confirmAndFlash(context, updater),
                    child: const Text('Update machine'),
                  ),
                ),
            ]),
          );
        },
      );
}
