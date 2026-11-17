import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// This build's version, set by the release build (GitHub Actions passes
/// --dart-define=APP_VERSION=1.0.N). Empty for a developer run, which never updates.
const appVersion = String.fromEnvironment('APP_VERSION');

enum UpdateState { upToDate, checking, available, downloading, installing, failed }

/// Looks for a newer EcoEarn release on GitHub when the laptop is online, and
/// installs it with one click: downloads the installer, runs it quietly (it
/// replaces the program, keeps the data and reopens EcoEarn) and closes the app.
class Updater extends ChangeNotifier {
  Updater({this.repository = 'GabJeungSook/ecoearn'});

  /// "owner/name" of the public GitHub repository the releases are published to.
  final String repository;

  static const _checkEvery = Duration(hours: 4);

  UpdateState _state = UpdateState.upToDate;
  String? _latestVersion;
  String? _installerUrl;
  String? _notes;
  double? _progress;
  String? _error;
  DateTime? _lastChecked;
  Timer? _timer;

  UpdateState get state => _state;

  /// The newer version on GitHub, when one is available.
  String? get latestVersion => _latestVersion;

  /// What changed (the release's description).
  String? get notes => _notes;

  /// Download progress 0–1 while [UpdateState.downloading].
  double? get progress => _progress;
  String? get error => _error;
  DateTime? get lastChecked => _lastChecked;

  /// False for developer runs (no version), which never look for updates.
  bool get enabled => appVersion.isNotEmpty;

  bool get updateAvailable => _state == UpdateState.available;

  /// Checks now and then every few hours. Safe to call once at startup.
  void start() {
    if (!enabled || _timer != null) return;
    unawaited(check());
    _timer = Timer.periodic(_checkEvery, (_) => check());
  }

  /// Asks GitHub for the latest release. Without internet it quietly stays as it was.
  Future<void> check() async {
    if (!enabled || _state == UpdateState.downloading || _state == UpdateState.installing) return;
    _state = UpdateState.checking;
    _error = null;
    notifyListeners();
    try {
      final release = await _getJson('https://api.github.com/repos/$repository/releases/latest');
      final tag = (release['tag_name'] as String? ?? '').replaceFirst(RegExp('^v'), '');
      final assets = (release['assets'] as List? ?? const []).cast<Map<String, dynamic>>();
      final installer = assets.where((a) => (a['name'] as String? ?? '').endsWith('-Setup.exe')).firstOrNull;
      _lastChecked = DateTime.now();
      if (installer != null && isNewer(tag, appVersion)) {
        _latestVersion = tag;
        _installerUrl = installer['browser_download_url'] as String;
        _notes = (release['body'] as String?)?.trim();
        _state = UpdateState.available;
      } else {
        _state = UpdateState.upToDate;
      }
    } catch (e) {
      // Usually just no internet; the next check tries again.
      _state = _latestVersion != null ? UpdateState.available : UpdateState.upToDate;
      debugPrint('Update check failed: $e');
    }
    notifyListeners();
  }

  /// Downloads and runs the installer, then [exitApp] closes EcoEarn so its
  /// files can be replaced. The installer reopens EcoEarn when it's done.
  Future<void> install({required Future<void> Function() exitApp}) async {
    final url = _installerUrl;
    if (url == null) return;
    _state = UpdateState.downloading;
    _progress = 0;
    _error = null;
    notifyListeners();
    try {
      final file = File(p.join(Directory.systemTemp.path, 'EcoEarn-Setup-$_latestVersion.exe'));
      await _download(url, file);
      _state = UpdateState.installing;
      notifyListeners();
      await Process.start(
        file.path,
        ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
        mode: ProcessStartMode.detached,
      );
      await exitApp();
    } catch (e) {
      _state = UpdateState.failed;
      _error = 'Could not download the update. Check the internet connection and try again. ($e)';
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> _getJson(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers
        ..set(HttpHeaders.userAgentHeader, 'EcoEarn-updater')
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close().timeout(const Duration(seconds: 20));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) throw HttpException('GitHub answered ${response.statusCode}');
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  Future<void> _download(String url, File file) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(url)); // GitHub redirects to its file storage; followed
      request.headers.set(HttpHeaders.userAgentHeader, 'EcoEarn-updater');
      final response = await request.close();
      if (response.statusCode != 200) throw HttpException('download answered ${response.statusCode}');
      final total = response.contentLength;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          _progress = received / total;
          notifyListeners();
        }
      }
      await sink.close();
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// True when version [a] (e.g. "1.0.12") is newer than [b]. Compares each number.
bool isNewer(String a, String b) {
  List<int> parts(String v) => v.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final xi = i < x.length ? x[i] : 0, yi = i < y.length ? y[i] : 0;
    if (xi != yi) return xi > yi;
  }
  return false;
}
