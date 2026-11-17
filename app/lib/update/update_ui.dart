import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../data/reports.dart';
import '../theme/app_theme.dart';
import '../widgets/stat_card.dart';
import 'updater.dart';

/// Closes EcoEarn right away (even the locked display screen) so the installer
/// can replace its files. Data is saved as it happens, so nothing is lost.
Future<void> exitForUpdate() async {
  await windowManager.setPreventClose(false);
  exit(0);
}

/// Asks once, then downloads and installs the update.
Future<void> confirmAndUpdate(BuildContext context, Updater updater) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Update to version ${updater.latestVersion}?'),
      content: Text(
        'EcoEarn downloads the update, closes for a moment and opens again by itself. '
        'Students, deposits and payments are kept.'
        '${(updater.notes ?? '').isEmpty ? '' : '\n\nWhat\'s new:\n${updater.notes}'}',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Later')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Update now')),
      ],
    ),
  );
  if (ok == true) await updater.install(exitApp: exitForUpdate);
}

/// Green button in the sidebar, shown only when an update is ready.
class SidebarUpdateButton extends StatelessWidget {
  const SidebarUpdateButton({super.key, required this.updater});

  final Updater updater;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: updater,
        builder: (context, _) {
          final busy = updater.state == UpdateState.downloading || updater.state == UpdateState.installing;
          if (!updater.updateAvailable && !busy) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Tooltip(
              message: busy ? 'Updating…' : 'Version ${updater.latestVersion} is available. Click to update.',
              child: Material(
                color: EcoColors.emerald,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: busy ? null : () => confirmAndUpdate(context, updater),
                  child: SizedBox(
                    width: 64,
                    height: 52,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      busy
                          ? SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                                value: updater.state == UpdateState.downloading ? updater.progress : null,
                              ),
                            )
                          : const Icon(Icons.system_update_alt, color: Colors.white, size: 20),
                      const SizedBox(height: 3),
                      const Text('Update',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

/// Settings card: the version running, update status, check and install buttons.
class UpdateCard extends StatelessWidget {
  const UpdateCard({super.key, required this.updater});

  final Updater updater;

  static String _time(DateTime t) =>
      '${monthNames[t.month - 1].substring(0, 3)} ${t.day}, '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: updater,
        builder: (context, _) {
          final (String status, Color color) = switch (updater.state) {
            _ when !updater.enabled => ('Developer build: updates are off.', EcoColors.muted),
            UpdateState.checking => ('Checking for updates…', EcoColors.muted),
            UpdateState.available => ('Version ${updater.latestVersion} is available.', EcoColors.emerald),
            UpdateState.downloading =>
              ('Downloading… ${((updater.progress ?? 0) * 100).round()}%', EcoColors.emerald),
            UpdateState.installing => ('Installing. EcoEarn will close and open again.', EcoColors.emerald),
            UpdateState.failed => (updater.error ?? 'The update failed.', EcoColors.coral),
            UpdateState.upToDate => (
                updater.lastChecked == null
                    ? 'Updates are checked when the laptop is online.'
                    : 'Up to date (checked ${_time(updater.lastChecked!)}).',
                EcoColors.muted
              ),
          };
          return Container(
            constraints: const BoxConstraints(maxWidth: 720),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: EcoColors.line),
            ),
            child: Row(children: [
              const IconBadge(icon: Icons.system_update_alt, color: EcoColors.emerald),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    'EcoEarn ${updater.enabled ? 'version $appVersion' : '(developer build)'}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(status, style: TextStyle(color: color)),
                  if (updater.state == UpdateState.downloading) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: updater.progress, minHeight: 5),
                  ],
                ]),
              ),
              const SizedBox(width: 12),
              if (updater.updateAvailable)
                SizedBox(
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: () => confirmAndUpdate(context, updater),
                    icon: const Icon(Icons.system_update_alt, size: 18),
                    label: Text('Update to ${updater.latestVersion}'),
                  ),
                )
              else
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: updater.enabled && updater.state != UpdateState.checking ? updater.check : null,
                    child: const Text('Check for updates'),
                  ),
                ),
            ]),
          );
        },
      );
}
