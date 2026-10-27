import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'account.dart';
import 'password_hash.dart';

const minPasswordLength = 6;

/// Login accounts and who is signed in right now.
class AuthService extends ChangeNotifier {
  AuthService(this._db);

  final Database _db;
  List<Account> _accounts = const [];
  Account? _current;

  List<Account> get accounts => _accounts;
  Account? get current => _current;

  /// False on first run, before the admin account is created.
  bool get hasAccounts => _accounts.isNotEmpty;

  Future<void> load() async {
    final rows = await _db.query('accounts', orderBy: 'role, username');
    _accounts = rows.map(Account.fromRow).toList();
    notifyListeners();
  }

  Account? _find(String username) {
    final name = username.trim().toLowerCase();
    return _accounts.where((a) => a.username == name).firstOrNull;
  }

  // Hashing is deliberately slow, so it runs off the UI thread.
  static Future<bool> _verify(String password, String hash) =>
      Isolate.run(() => verifyPassword(password, hash));

  /// Returns an error message, or null when signed in.
  Future<String?> login(String username, String password) async {
    final account = _find(username);
    if (account == null || !await _verify(password, account.passwordHash)) {
      return 'Wrong username or password.';
    }
    _current = account;
    notifyListeners();
    return null;
  }

  void logout() {
    _current = null;
    notifyListeners();
  }

  /// True if [password] belongs to any admin account (used to unlock the display kiosk).
  Future<bool> isAdminPassword(String password) async {
    for (final admin in _accounts.where((a) => a.role == Role.admin)) {
      if (await _verify(password, admin.passwordHash)) return true;
    }
    return false;
  }

  /// Creates an account, or updates [existing]. [password] may be empty when
  /// updating to keep the current one. Returns an error message, or null on success.
  Future<String?> save({
    Account? existing,
    required String username,
    required String displayName,
    required Role role,
    required String password,
  }) async {
    final name = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9._-]{3,}$').hasMatch(name)) {
      return 'Username needs at least 3 characters: letters, numbers, dot, dash or underscore.';
    }
    if (displayName.trim().isEmpty) return 'Name is required.';
    if (existing == null || password.isNotEmpty) {
      if (password.length < minPasswordLength) {
        return 'Password needs at least $minPasswordLength characters.';
      }
    }
    final other = _find(name);
    if (other != null && other.id != existing?.id) return 'Username "$name" is already taken.';
    if (existing?.role == Role.admin && role != Role.admin && _adminCount == 1) {
      return 'This is the only admin account, so its role can\'t be changed.';
    }

    final row = <String, Object?>{
      'username': name,
      'display_name': displayName.trim(),
      'role': role.name,
      if (password.isNotEmpty) 'password_hash': await Isolate.run(() => hashPassword(password)),
    };
    if (existing == null) {
      await _db.insert('accounts', {...row, 'created_at': DateTime.now().toIso8601String()});
    } else {
      await _db.update('accounts', row, where: 'id = ?', whereArgs: [existing.id]);
    }
    await load();
    if (_current != null) {
      _current = _accounts.where((a) => a.id == _current!.id).firstOrNull;
      notifyListeners();
    }
    return null;
  }

  int get _adminCount => _accounts.where((a) => a.role == Role.admin).length;

  /// Returns an error message, or null on success.
  Future<String?> delete(Account account) async {
    if (account.id == _current?.id) return 'You can\'t delete the account you are signed in with.';
    if (account.role == Role.admin && _adminCount == 1) return 'The last admin account can\'t be deleted.';
    await _db.delete('accounts', where: 'id = ?', whereArgs: [account.id]);
    await load();
    return null;
  }
}
