class AppUser {
  const AppUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.instrument,
    required this.avatarInitials,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String instrument;
  final String avatarInitials;

  String get fullName => '$firstName $lastName';

  AppUser copyWith({
    String? firstName,
    String? lastName,
    String? instrument,
  }) {
    return AppUser(
      id: id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email,
      instrument: instrument ?? this.instrument,
      avatarInitials: avatarInitials,
    );
  }
}