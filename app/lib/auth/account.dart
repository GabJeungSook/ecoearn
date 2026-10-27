enum Role {
  /// Everything: live screen, students, reports, accounts.
  admin('Admin', 'Full access'),

  /// Locked fullscreen live screen for the machine's monitor.
  display('Display', 'Fullscreen live screen only'),

  /// Views imported data: reports and students, read-only.
  officer('Officer', 'View imported data and reports');

  const Role(this.label, this.description);

  final String label;
  final String description;
}

class Account {
  const Account({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    required this.passwordHash,
  });

  factory Account.fromRow(Map<String, Object?> row) => Account(
        id: row['id'] as int,
        username: row['username'] as String,
        displayName: row['display_name'] as String,
        role: Role.values.byName(row['role'] as String),
        passwordHash: row['password_hash'] as String,
      );

  final int id;
  final String username;
  final String displayName;
  final Role role;
  final String passwordHash;
}
