import 'group_member.dart';

class WorshipGroup {
  const WorshipGroup({
    required this.id,
    required this.name,
    required this.churchName,
    required this.members,
    required this.accentColorValue,
  });

  final String id;
  final String name;
  final String churchName;
  final List<GroupMember> members;
  final int accentColorValue;

  int get memberCount => members.length;
}