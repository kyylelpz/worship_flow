import 'setlist_item.dart';

enum SetlistStatus { draft, published }

class Setlist {
  const Setlist({
    required this.id,
    required this.groupId,
    required this.name,
    required this.serviceDateTime,
    required this.status,
    required this.publishedItems,
    this.draftItems,
  });

  final String id;
  final String groupId;
  final String name;
  final DateTime serviceDateTime;
  final SetlistStatus status;
  final List<SetlistItem> publishedItems;
  final List<SetlistItem>? draftItems;

  List<SetlistItem> get displayItems => publishedItems;
  int get songCount => publishedItems.length;
  bool get hasDraftChanges => draftItems != null;
  bool get isPublished => status == SetlistStatus.published;
  bool get isUpcoming => serviceDateTime.isAfter(DateTime.now());

  Setlist copyWith({
    String? name,
    DateTime? serviceDateTime,
    SetlistStatus? status,
    List<SetlistItem>? publishedItems,
    List<SetlistItem>? draftItems,
    bool clearDraft = false,
  }) {
    return Setlist(
      id: id,
      groupId: groupId,
      name: name ?? this.name,
      serviceDateTime: serviceDateTime ?? this.serviceDateTime,
      status: status ?? this.status,
      publishedItems: publishedItems ?? this.publishedItems,
      draftItems: clearDraft ? null : (draftItems ?? this.draftItems),
    );
  }
}
