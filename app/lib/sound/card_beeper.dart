import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../serial/device_event.dart';

/// Plays a short beep on the laptop every time a card is tapped on the reader.
class CardBeeper {
  CardBeeper(Stream<DeviceEvent> events) {
    _player.setReleaseMode(ReleaseMode.stop);
    _subscription = events.listen((event) {
      if (event is CardEvent) unawaited(_beep());
    });
  }

  final _player = AudioPlayer();
  late final StreamSubscription<DeviceEvent> _subscription;

  Future<void> _beep() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/card_beep.wav'), volume: 1);
    } catch (e) {
      debugPrint('Card beep failed: $e'); // a missing sound must never stop the app
    }
  }

  void dispose() {
    _subscription.cancel();
    _player.dispose();
  }
}
