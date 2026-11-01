enum MembershipPosition {
  vocalist('Vocalist'),
  acousticGuitar('Acoustic Guitar'),
  electricGuitar('Electric Guitar'),
  bassGuitar('Bass Guitar'),
  keyboard('Keyboard'),
  drums('Drums'),
  other('Other');

  const MembershipPosition(this.label);
  final String label;
}
