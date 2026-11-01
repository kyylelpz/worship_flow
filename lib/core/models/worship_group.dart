import 'group_member.dart';

class WorshipGroup {
  const WorshipGroup({
    required this.id,
    required this.name,
    required this.churchName,
    required this.members,
    required this.accentColorValue,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String churchName;
  final List<GroupMember> members;
  final int accentColorValue;
  final String? createdBy;
  final DateTime? createdAt, updatedAt;

  int get memberCount => members.length;
}
