enum UserRole {
  administrator('Administrator'),
  worshipLeader('Worship Leader'),
  worshipTrainee('Worship Trainee');

  const UserRole(this.label);
  final String label;

  bool get canManageMembers => this == UserRole.administrator;
  bool get canManageSongs =>
      this == UserRole.administrator || this == UserRole.worshipLeader;
  bool get canManageSetlists =>
      this == UserRole.administrator || this == UserRole.worshipLeader;
  bool get canEnterLiveMode => true;
}