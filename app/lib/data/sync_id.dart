import 'dart:math';

final _random = Random.secure();

/// A permanent, globally unique ID for a student or deposit (32 hex digits).
/// Officer imports merge records by it, so the same record from two exports,
/// or from two laptops, is never counted twice.
String newSyncId() => List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
