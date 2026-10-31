import '../models/setlist.dart';
import '../models/setlist_item.dart';

final _now = DateTime.now();
DateTime _offset({required int days, int hour = 10, int minute = 0}) {
  final base = _now.add(Duration(days: days));
  return DateTime(base.year, base.month, base.day, hour, minute);
}

final mockSetlists = <Setlist>[
  // 1. Published / upcoming — the default service card on Setlists screen.
  Setlist(
    id: 'setlist-1',
    groupId: 'group-1',
    name: 'Sunday Morning Service',
    serviceDateTime: _offset(days: 7, hour: 9, minute: 30),
    status: SetlistStatus.published,
    publishedItems: const [
      SetlistItem(
        songId: 'song-1',
        arrangementId: 'song-1-arr-full',
        performanceKey: 'G',
      ),
      SetlistItem(
        songId: 'song-6',
        arrangementId: 'song-6-arr-full',
        performanceKey: 'B',
      ),
      SetlistItem(
        songId: 'song-3',
        arrangementId: 'song-3-arr-full',
        performanceKey: 'C',
      ),
    ],
  ),

  // 2. Published / upcoming, WITH unpublished draft changes — banner test case.
  Setlist(
    id: 'setlist-2',
    groupId: 'group-1',
    name: 'Midweek Rehearsal',
    serviceDateTime: _offset(days: 3, hour: 19, minute: 0),
    status: SetlistStatus.published,
    publishedItems: const [
      SetlistItem(
        songId: 'song-2',
        arrangementId: 'song-2-arr-full',
        performanceKey: 'D',
      ),
      SetlistItem(
        songId: 'song-7',
        arrangementId: 'song-7-arr-full',
        performanceKey: 'F',
      ),
    ],
    draftItems: const [
      SetlistItem(
        songId: 'song-2',
        arrangementId: 'song-2-arr-full',
        performanceKey: 'D',
      ),
      SetlistItem(
        songId: 'song-7',
        arrangementId: 'song-7-arr-full',
        performanceKey: 'F',
      ),
      SetlistItem(
        songId: 'song-4',
        arrangementId: 'song-4-arr-full',
        performanceKey: 'A',
      ),
    ],
  ),

  // 3. Draft / upcoming — never published. Only editors should see the editor.
  Setlist(
    id: 'setlist-3',
    groupId: 'group-1',
    name: 'Youth Night — October',
    serviceDateTime: _offset(days: 14, hour: 18, minute: 30),
    status: SetlistStatus.draft,
    publishedItems: const [],
    draftItems: const [
      SetlistItem(
        songId: 'song-8',
        arrangementId: 'song-8-arr-full',
        performanceKey: 'Ab',
      ),
      SetlistItem(
        songId: 'song-5',
        arrangementId: 'song-5-arr-full',
        performanceKey: 'Em',
      ),
    ],
  ),

  // 4. Published / previous — the default in "Previous" filter.
  Setlist(
    id: 'setlist-4',
    groupId: 'group-1',
    name: 'Sunday Morning Service',
    serviceDateTime: _offset(days: -7, hour: 9, minute: 30),
    status: SetlistStatus.published,
    publishedItems: const [
      SetlistItem(
        songId: 'song-2',
        arrangementId: 'song-2-arr-full',
        performanceKey: 'D',
      ),
      SetlistItem(
        songId: 'song-7',
        arrangementId: 'song-7-arr-full',
        performanceKey: 'F',
      ),
    ],
  ),

  // Bonus group-2 setlist so switching groups visibly changes the list.
  Setlist(
    id: 'setlist-5',
    groupId: 'group-2',
    name: 'Friday Youth Service',
    serviceDateTime: _offset(days: 5, hour: 19, minute: 0),
    status: SetlistStatus.published,
    publishedItems: const [
      SetlistItem(
        songId: 'song-4',
        arrangementId: 'song-4-arr-full',
        performanceKey: 'A',
      ),
      SetlistItem(
        songId: 'song-6',
        arrangementId: 'song-6-arr-full',
        performanceKey: 'B',
      ),
    ],
  ),
];