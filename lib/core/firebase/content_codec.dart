import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/song.dart';
import '../models/arrangement.dart';
import '../models/vocalist_key.dart';
import '../models/setlist.dart';
import '../models/setlist_item.dart';

Map<String, dynamic> arrangementData(Arrangement a) => {
      'id': a.id,
      'name': a.name.trim(),
      'bpm': a.bpm,
      'timeSignature': a.timeSignature,
      'chordProSource': a.chordProSource,
      'referenceLink': a.referenceLink.trim()
    };
Map<String, dynamic> songData(String group, Song s) => {
      'id': s.id,
      'groupId': group,
      'title': s.title.trim(),
      'artist': s.artist.trim(),
      'category': s.category.trim(),
      'isFavorite': s.isFavorite,
      'vocalistKeys': [
        for (final v in s.vocalistKeys)
          {'vocalistName': v.vocalistName.trim(), 'key': v.key.trim()}
      ],
      'arrangementIds': s.arrangements.map((a) => a.id).toList(),
      'arrangements': {for (final a in s.arrangements) a.id: arrangementData(a)}
    };
Song songFromData(Map<String, dynamic> d) => Song(
        id: d['id'] as String,
        title: d['title'] as String,
        artist: d['artist'] as String,
        category: d['category'] as String,
        isFavorite: d['isFavorite'] as bool,
        vocalistKeys: [
          for (final v in d['vocalistKeys'] as List)
            VocalistKey(
                vocalistName: v['vocalistName'] as String,
                key: v['key'] as String)
        ],
        arrangements: [
          for (final id in d['arrangementIds'] as List)
            Arrangement(
                id: id as String,
                name: d['arrangements'][id]['name'] as String,
                bpm: d['arrangements'][id]['bpm'] as int,
                timeSignature: d['arrangements'][id]['timeSignature'] as String,
                chordProSource:
                    d['arrangements'][id]['chordProSource'] as String,
                referenceLink: d['arrangements'][id]['referenceLink'] as String)
        ]);

Map<String, dynamic> itemData(SetlistItem i) => {
      'songId': i.songId,
      'arrangementId': i.arrangementId,
      'performanceKey': i.performanceKey,
      'vocalistName': i.vocalistName
    };
SetlistItem itemFromData(dynamic d) => SetlistItem(
    songId: d['songId'] as String,
    arrangementId: d['arrangementId'] as String,
    performanceKey: d['performanceKey'] as String,
    vocalistName: d['vocalistName'] as String?);
Map<String, dynamic> setlistData(Setlist s) => {
      'id': s.id,
      'groupId': s.groupId,
      'name': s.name.trim(),
      'serviceDateTime': Timestamp.fromDate(s.serviceDateTime),
      'status': s.status.name,
      'publishedItems': s.publishedItems.map(itemData).toList(),
      'draftItems': s.draftItems?.map(itemData).toList(),
      'publishedKeys':
          {for (final i in s.publishedItems) i.arrangementId}.toList()..sort(),
      'draftKeys': {
        for (final i in s.draftItems ?? <SetlistItem>[]) i.arrangementId
      }.toList()
        ..sort(),
      'referenceKeys': {
        for (final i in [...s.publishedItems, ...?s.draftItems]) i.arrangementId
      }.toList()
        ..sort()
    };
Setlist setlistFromData(Map<String, dynamic> d) => Setlist(
    id: d['id'] as String,
    groupId: d['groupId'] as String,
    name: d['name'] as String,
    serviceDateTime: (d['serviceDateTime'] as Timestamp).toDate(),
    status: SetlistStatus.values.byName(d['status'] as String),
    revision: d['revision'] as int? ?? 0,
    publishedItems: (d['publishedItems'] as List).map(itemFromData).toList(),
    draftItems: (d['draftItems'] as List?)?.map(itemFromData).toList());

// Firestore map iteration order is not a semantic change. Lists remain ordered.
bool sameContentValue(dynamic a, dynamic b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every(
            (key) => b.containsKey(key) && sameContentValue(a[key], b[key]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(a.length, (i) => i)
            .every((i) => sameContentValue(a[i], b[i]));
  }
  return a == b;
}
