import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

// Passwords are stored as PBKDF2-HMAC-SHA256 with a random salt:
//   pbkdf2-sha256$<iterations>$<salt base64>$<hash base64>
const _scheme = 'pbkdf2-sha256';
const _iterations = 60000;

String hashPassword(String password) {
  final random = Random.secure();
  final salt = List<int>.generate(16, (_) => random.nextInt(256));
  final hash = _pbkdf2(password, salt, _iterations);
  return '$_scheme\$$_iterations\$${base64.encode(salt)}\$${base64.encode(hash)}';
}

bool verifyPassword(String password, String stored) {
  final parts = stored.split('\$');
  if (parts.length != 4 || parts[0] != _scheme) return false;
  final iterations = int.tryParse(parts[1]);
  if (iterations == null) return false;

  final expected = base64.decode(parts[3]);
  final actual = _pbkdf2(password, base64.decode(parts[2]), iterations);
  // Compare every byte so the time taken doesn't reveal where they differ.
  var diff = expected.length ^ actual.length;
  for (var i = 0; i < min(expected.length, actual.length); i++) {
    diff |= expected[i] ^ actual[i];
  }
  return diff == 0;
}

// One 32-byte block is all a SHA-256 key needs.
List<int> _pbkdf2(String password, List<int> salt, int iterations) {
  final hmac = Hmac(sha256, utf8.encode(password));
  var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final result = List<int>.of(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < result.length; j++) {
      result[j] ^= u[j];
    }
  }
  return result;
}
