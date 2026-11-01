import '../models/arrangement.dart';
import '../models/song.dart';
import '../models/vocalist_key.dart';

// All songs and lyrics are original fictional content created for this
// application foundation. Do not replace with copyrighted material.
const _chordProSongOne = '''
{title: Anchor of the Morning}
{key: G}
{tempo: 74}

{section: Verse 1}
[G]Rise with the [D]dawn, we [Em]lift our [C]voice
[G]Steady the [D]hands that [C]hold Your [G]choice
[Em]Every [C]shadow [G]fades a[D]way
[Em]In the [C]light of [D]endless [G]day

{section: Chorus}
[C]You are the [G]anchor of the [D]morning
[C]You are the [Em]harbor in the [D]storm
[C]We will [G]sing with [D]every [Em]breath
[C]Every [D]note for [G]Your glo[G/B]ry

{section: Bridge}
[Am]Hold us [C]close, [G]never [D]let [Em]go
[Am]Hold us [C]close, [D]we are [G]Yours
''';

const _chordProSongTwo = '''
{title: Mercy Like a River}
{key: D}
{tempo: 68}

{section: Verse 1}
[D]Quiet [A]waters, [Bm]mercy [G]flows
[D]Washing [A]over [G]all we [D]know
[Bm]Grace that [G]covers [D]every [A]stain
[Bm]Love that [G]calls us [A]home a[D]gain

{section: Chorus}
[G]Mercy like a [D]river, [A]endless and [Bm]wide
[G]Carry us [D]closer, [A]safe in Your [D]side
''';

const _chordProSongThree = '''
{title: Silent Hallelujah}
{key: C}
{tempo: 80}

{section: Verse 1}
[C]In the [G]stillness [Am]we will [F]wait
[C]Trusting [G]every [F]word You [C]say

{section: Chorus}
[F]Silent [C]hallelu[G]jah, [Am]rises [F]from the [G]deep
[F]Even [C]in the [G]waiting, [Am]You are [F]all we [G]keep
''';

const _chordProSongFour = '''
{title: Bright Horizon}
{key: A}
{tempo: 88}

{section: Verse 1}
[A]Colors [E]break a[F#m]cross the [D]sky
[A]Hope is [E]rising, [D]drawing [A]nigh

{section: Chorus}
[D]Bright ho[A]rizon, [E]light of [F#m]grace
[D]Every [A]morning, [E]every [A]place
''';

const _chordProSongFive = '''
{title: Carried Through the Fire}
{key: Em}
{tempo: 72}

{section: Verse 1}
[Em]When the [C]flames sur[G]round our [D]feet
[Em]You are [C]faithful, [D]You are [Em]near

{section: Chorus}
[C]Carried [G]through the [D]fire
[C]Held with[Em]in Your [D]hands
''';

const _chordProSongSix = '''
{title: Open Hands}
{key: B}
{tempo: 76}

{section: Verse 1}
[B]Open [F#]hands, [G#m]open [E]heart
[B]Every [F#]part of [E]who we [B]are

{section: Chorus}
[E]Take it [B]all, [F#]take it [G#m]all
[E]We are [B]Yours, [F#]we will [B]call
''';

const _chordProSongSeven = '''
{title: Faithful in the Waiting}
{key: F}
{tempo: 66}

{section: Verse 1}
[F]Faithful [C]in the [Dm]wai[Bb]ting
[F]Faithful [C]in the [Bb]night

{section: Chorus}
[Bb]You have [F]never [C]let us [Dm]go
[Bb]You will [F]never [C]let us [F]go
''';

const _chordProSongEight = '''
{title: King of Every Season}
{key: Ab}
{tempo: 84}

{section: Verse 1}
[Ab]Spring and [Eb]summer, [Fm]winter [Db]rain
[Ab]Every [Eb]season [Db]sings Your [Ab]name

{section: Chorus}
[Db]King of [Ab]every [Eb]season
[Db]King of [Fm]every [Eb]day
''';

const mockSongs = <Song>[
  Song(
    id: 'song-1',
    title: 'Anchor of the Morning',
    artist: 'Worship Flow Originals',
    category: 'Praise',
    vocalistKeys: [
      VocalistKey(vocalistName: 'Jordan', key: 'G'),
      VocalistKey(vocalistName: 'Avery', key: 'A'),
    ],
    isFavorite: true,
    arrangements: [
      Arrangement(
        id: 'song-1-arr-full',
        name: 'Full Band',
        bpm: 74,
        timeSignature: '4/4',
        chordProSource: _chordProSongOne,
      ),
      Arrangement(
        id: 'song-1-arr-acoustic',
        name: 'Acoustic',
        bpm: 72,
        timeSignature: '4/4',
        chordProSource: _chordProSongOne,
      ),
    ],
  ),
  Song(
    id: 'song-2',
    title: 'Mercy Like a River',
    artist: 'Worship Flow Originals',
    category: 'Worship',
    vocalistKeys: [
      VocalistKey(vocalistName: 'Jordan', key: 'D'),
      VocalistKey(vocalistName: 'Noah', key: 'E'),
    ],
    isFavorite: false,
    arrangements: [
      Arrangement(
        id: 'song-2-arr-full',
        name: 'Full Band',
        bpm: 68,
        timeSignature: '4/4',
        chordProSource: _chordProSongTwo,
      ),
    ],
  ),
  Song(
    id: 'song-3',
    title: 'Silent Hallelujah',
    artist: 'Worship Flow Originals',
    category: 'Worship',
    vocalistKeys: [
      VocalistKey(vocalistName: 'Avery', key: 'C'),
    ],
    isFavorite: true,
    arrangements: [
      Arrangement(
        id: 'song-3-arr-full',
        name: 'Full Band',
        bpm: 80,
        timeSignature: '4/4',
        chordProSource: _chordProSongThree,
      ),
    ],
  ),
  Song(
    id: 'song-4',
    title: 'Bright Horizon',
    artist: 'Worship Flow Originals',
    category: 'Praise',
    vocalistKeys: [
      VocalistKey(vocalistName: 'Jordan', key: 'A'),
    ],
    isFavorite: false,
    arrangements: [
      Arrangement(
        id: 'song-4-arr-full',
        name: 'Full Band',
        bpm: 88,
        timeSignature: '4/4',
        chordProSource: _chordProSongFour,
      ),
    ],
  ),
  Song(
    id: 'song-5',
    title: 'Carried Through the Fire',
    artist: 'Worship Flow Originals',
    category: 'Worship',
    vocalistKeys: [
      VocalistKey(vocalistName: 'Noah', key: 'Em'),
    ],
    isFavorite: false,
    arrangements: [
      Arrangement(
        id: 'song-5-arr-full',
        name: 'Full Band',
        bpm: 72,
        timeSignature: '4/4',
        chordProSource: _chordProSongFive,
      ),
    ],
  ),
  Song(
    id: 'song-6',
    title: 'Open Hands',
    artist: 'Worship Flow Originals',
    category: 'Worship',
    vocalistKeys: [
      VocalistKey(vocalistName: 'Jordan', key: 'B'),
      VocalistKey(vocalistName: 'Avery', key: 'C'),
    ],
    isFavorite: true,
    arrangements: [
      Arrangement(
        id: 'song-6-arr-full',
        name: 'Full Band',
        bpm: 76,
        timeSignature: '4/4',
        chordProSource: _chordProSongSix,
      ),
    ],
  ),
  Song(
    id: 'song-7',
    title: 'Faithful in the Waiting',
    artist: 'Worship Flow Originals',
    category: 'Worship',
    vocalistKeys: [
      VocalistKey(vocalistName: 'Avery', key: 'F'),
    ],
    isFavorite: false,
    arrangements: [
      Arrangement(
        id: 'song-7-arr-full',
        name: 'Full Band',
        bpm: 66,
        timeSignature: '4/4',
        chordProSource: _chordProSongSeven,
      ),
    ],
  ),
  Song(
    id: 'song-8',
    title: 'King of Every Season',
    artist: 'Worship Flow Originals',
    category: 'Praise',
    vocalistKeys: [
      VocalistKey(vocalistName: 'Jordan', key: 'Ab'),
    ],
    isFavorite: false,
    arrangements: [
      Arrangement(
        id: 'song-8-arr-full',
        name: 'Full Band',
        bpm: 84,
        timeSignature: '4/4',
        chordProSource: _chordProSongEight,
      ),
    ],
  ),
];
